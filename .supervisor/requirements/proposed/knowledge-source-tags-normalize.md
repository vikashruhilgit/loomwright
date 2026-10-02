# `knowledge_sources_used` tags are spelled inconsistently, splitting the counts

## Status: proposed

> **Origin (2026-10-02).** `/insights` rebuild in session 1378d676, in the "Knowledge sources (memory APPLY)" section.

## Evidence
The same source appears under several spellings, so each count is split across rows:
- `project_memory` (14) and `project-memory` (2)
- `house_rules` (4), `house-rules` (2) and `house_rules:process` (1)
- `prior_churn` (2) and `prior-churn` (2)
- `lessons` (3) next to `lessons:<category>`

The command doc describes an open, lowercase set (`project_memory`, `lessons:<category>`, `agent_memory:<agent>`,
`twin:<path>`, `brain_context`). Nothing enforces a separator, and new tags (`house_rules`, `prior_churn`,
`postmortem_ledger`, `brief-conformance`) appear without being documented. The headline "16 of 88 runs report a source"
is unaffected, because it counts runs. The per-tag table and any "which memory actually gets used" reading are wrong.

## Scope (recommendation)
- Pick one canonical form (underscore, per the documented set) and list the full tag vocabulary in one place, the
  RESULT_SCHEMAS `session_end` contract. Point the emitting prompts at that list instead of restating it.
- Normalize when the tag is written: in whatever emits `knowledge_sources_used` (the Supervisor `session_end` step),
  lower-case it and map `-` to `_` in the base tag, keeping the `:<qualifier>` part verbatim.
- Normalize when the tag is read, in `build-insights.sh`, so existing logs aggregate correctly without being rewritten.
- Fixture: `project-memory` and `project_memory` aggregate to one row.
