# Task Plan — meta-sync-untested-fallbacks

Source: .supervisor/jobs/in-progress/2026-10-05-meta-sync-untested-fallbacks.md (AC-1..AC-7)
Mode: single-agent (Decomposition Threshold: one task; no named reason to split)

## EPIC meta-sync-untested-fallbacks
- [ ] meta-sync-untested-fallbacks-1 — Two meta-sync test legs + mutation controls, fragment, bump
  - AC: ALL (AC-1 .. AC-7) per brief
  - Files: loomwright/scripts/test-meta-sync.sh (modify); changelog.d/meta-sync-followups-01-untested-push-and-base-fallbacks.md [TO BE CREATED]; bump touches CHANGELOG.md, loomwright/.claude-plugin/plugin.json, .claude-plugin/marketplace.json (script-only)
  - Leg numbering: legs 34 (push_failed exhaustion), 35 (missing meta-base object: push/pull/conflict); controls 36, 37 after controls 20/21
  - Blocked by: none
  - Gate: outputs_verified + bash loomwright/scripts/test-meta-sync.sh + bash scripts/ci-local.sh; Phase 4.5 integrated review once after FINALIZE (no per-task review subtask)
  - Skills: skills/unit-testing/SKILL.md, skills/quality-checklist/SKILL.md
  - Commit order: test change -> fragment -> bump-version.sh as LAST commit
