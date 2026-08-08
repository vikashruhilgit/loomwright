---
name: fail-safe-exit-0
description: Read-only/probe/advisory scripts must always exit 0; the self-test must assert exit 0 on the missing-dependency path
metadata:
  type: feedback
---
Rule: any read-only gather/probe/persist/advisory script (pr-postmortem-gather,
session-resume observability_probe, run-eval, build-insights) must ALWAYS exit 0 and
never invoke side-effecting commands (no `docker up`); its self-test must explicitly
assert exit 0 when the dependency is missing (no gh, no daemon, no corpus, no network).
**Why:** these run inside or alongside a live session/hook — a non-zero exit or a
side effect breaks the host flow. **How to apply:** when assessing probe/advisory
tooling coverage, the missing-dep exit-0 assertion is a required test case, not optional.
