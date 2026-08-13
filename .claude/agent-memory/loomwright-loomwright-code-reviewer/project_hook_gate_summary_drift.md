---
name: hook-gate-summary-drift
description: When hook-dispatch-on-pr-create.sh session-scope gate logic changes, two prose summaries under-describe it and are NOT doc-currency-scanned
metadata:
  type: project
---

When `hook-dispatch-on-pr-create.sh`'s session-scope authorization logic changes, TWO current-state prose summaries restate the gate and drift to under-describe it:
1. `CLAUDE.md` Plugin Hooks table — the `PostToolUse (Bash)` row ("Session-scope gated (in-progress job + state.md Status≠... + head-branch match)").
2. `loomwright/agents/supervisor.md` ~line 1038 "Hook backstop" paragraph ("session-scope gated (in-progress job exists AND state.md Status is not ... AND PR head branch matches ...)").

**Why:** v14.38.0 added a Source-2 autonomous `state.json` fallback + removed the stale-terminal-state short-circuit, but both summaries still described the pre-PR single-source (state.md-only) gate. Neither is doc-currency-CI-scanned (phase/gate enumerations are on the explicit "gate does NOT scan" list in CLAUDE.md §Doc currency). They are not FALSE (they state a correct authorized subset = Source 1) so they read as MEDIUM under-description, not a contradiction — the authoritative truth lives in the hook header + the release banner.

**How to apply:** on any PR touching the hook's gate/authorization logic, grep these two surfaces for "session-scope gated" / "state.md Status" and confirm they still describe the full authorization set (now Source-1 state.md OR Source-2 unique autonomous state.json). Flag as `drift`/`workflow` MEDIUM if they lag. Related: [[agent-command-mirror-drift-on-fixes]].
