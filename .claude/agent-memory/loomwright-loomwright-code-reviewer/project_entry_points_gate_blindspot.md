---
name: entry-points-gate-blindspot
description: RESOLVED — check-doc-currency.sh now scans "(N entry points)" (and "N slash commands" in README incl. the historical v14.0.0 banner); blind spot closed
metadata:
  type: project
---

RESOLVED (verified 2026-06-13, v14.24.0 review): `scripts/check-doc-currency.sh` now includes `check_count '[0-9]+ entry points'` and `check_count '[0-9]+ slash commands'` among its patterns, and the FILES allowlist covers README.md, .claude-plugin/README.md, CLAUDE.md, agent-help.md, SKILLS_INDEX.md. CLAUDE.md:30 [pins: `entry points`] "(N entry points)" is no longer a silent-drift surface.

**Consequence worth keeping:** the gate scans `[0-9]+ slash commands` even inside HISTORICAL phrasing (README's "NEW in v14.0.0" banner trailing counts) — so on a count bump those historical-looking lines MUST be updated to current values; don't flag such updates as "editing history", they are gate-forced. Related: [[half-fixed-example-classes]] item 5.
