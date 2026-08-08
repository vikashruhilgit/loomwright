---
name: count-version-gate-blindspots
description: Count/version drift is the top late-stage failure; gate regexes miss phrasing variants — sweep all surfaces + all phrasings
metadata:
  type: feedback
---
Rule: after any agent/command/skill/hook add-or-remove or version bump, the count and
version strings must be updated across ALL surfaces (plugin.json, marketplace.json,
CLAUDE.md, README, agent-help, SKILLS_INDEX) in the same change, and the doc-currency
gate's regex must cover EVERY phrasing variant (`N slash commands` AND `N entry points`).
**Why:** this is the single most common late-stage CI failure here; exact-phrase gates
have blind spots that let a stale count pass green (polish-gate-and-delta fixed the
`N entry points` blind spot; setup-observability ST5 needed a retry to land the sweep).
**How to apply:** treat count/version surfaces as a multi-file invariant; grep bare
numbers with flexible separators, not just the canonical phrase. See [[infra-self-test-contract]].
