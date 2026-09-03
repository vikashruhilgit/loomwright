---
name: loomwright:beta
description: SYNTHETIC fixture agent for test-build-floor.sh. Not a real agent. Carries NO color:, which is the omitted-field case.
tools: Read, Write, Edit
model: opus
maxTurns: 40
disallowedTools: Write, NotebookEdit
---

# Beta (fixture)

Two things at once, both load-bearing:

1. NO `color:` line - so `color` must be OMITTED from this row, never defaulted to a
   plausible neutral.
2. `disallowedTools` contains `Write` and `NotebookEdit` but NOT `Edit` as a whole token,
   so `read_only` must be FALSE. A substring test for `Edit` matches `NotebookEdit` and
   would wrongly report this agent read-only; that is precisely the assertion this row buys.
