---
name: otel-labeler-session-lag
description: set-otel-resource-attrs.sh SessionStart hook has an inherent one-session-lag (writes settings.local.json at SessionStart, but that file is READ at session start before the hook runs); the init-tail + $CLAUDE_ENV_FILE write are the intentional mitigations — not a bug
metadata:
  type: project
---
The v14.47.0 per-project OTel labeler (`set-otel-resource-attrs.sh`) writes `<project>/.claude/settings.local.json` `.env.OTEL_RESOURCE_ATTRIBUTES` from a SessionStart hook, but Claude Code READS settings.local.json's env at session start BEFORE the hook fires.

**Why:** the label therefore takes effect from the NEXT session for a brand-new repo. This is an inherent ordering property, NOT a defect.

**How to apply:** do NOT flag the one-session-lag as a correctness bug. The two intentional mitigations cover the enabling session: (1) the `/setup observability` init-tail invokes the labeler synchronously during init; (2) the script best-effort appends `export OTEL_RESOURCE_ATTRIBUTES=...` to `$CLAUDE_ENV_FILE` when writable. OBSERVABILITY.md documents this caveat explicitly. The gate re-reads `~/.claude/settings.json` fresh each run (not cached env), so the init-tail sees the just-merged telemetry flag — no stale-env hazard. See [[entry-points-gate-blindspot]] for the doc-currency-gate coverage limits that DON'T apply here (this change passed both gates clean).
