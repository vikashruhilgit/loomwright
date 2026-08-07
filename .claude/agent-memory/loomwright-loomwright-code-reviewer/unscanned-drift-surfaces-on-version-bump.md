---
name: unscanned-drift-surfaces-on-version-bump
description: Repo surfaces check-doc-currency.sh does NOT scan that recurringly drift on version bumps — check these first in every consistency audit
metadata:
  type: project
---

On any Loomwright version-bump PR, `check-doc-currency.sh` + `validate-version.sh` green is necessary but NOT sufficient. **Why:** found in the v15.2.0 audit (PR #89) — both gates passed while two drift surfaces went stale. **How to apply:** in consistency_audit mode, additionally check:

1. **README.md "NEW in vX.Y.Z" banner stack** (top of README) — was a per-release convention through v15.20.0 (sequential banner for every version v15.11.0–v15.20.0, no gaps). **Discontinued as of the v15.21.0 "CLAUDE.md diet" PR** (confirmed 2026-08-04 reviewing PR #124/v15.23.0: README still tops out at "NEW in v15.20.0" three releases later, v15.21/15.22/15.23 all have no banner) — that PR's own changelog explicitly moved full release narrative to CHANGELOG.md and deleted redundant version restatements elsewhere. **Do NOT flag a missing README banner as new drift on any PR ≥ v15.21.0** unless a fresh banner reappears and then a later release skips one (which would re-establish a live convention). Re-verify this discontinuation is still true before trusting it, since a human could revive the banner practice at any time.
2. **Skill frontmatter `version:`/`lastUpdated:`** — substantive SKILL.md edits should bump these, and the matching **SKILLS_INDEX.md per-row cells** should be refreshed (CLAUDE.md names these cells "recurring drift, integration-review-only"). Pre-existing example: automate-loop index row said 1.0.0/2026-06-20 while its frontmatter said 1.1.0/2026-06-22. **Confirmed still live 2026-08-04** — PR #124 added a new normative RULE paragraph to `supervisor-readiness/SKILL.md` §"Subtask Structure" without bumping `version: "1.3.0"` / `lastUpdated: "2026-07-31"` (or the matching SKILLS_INDEX.md row), flagged as drift/version_secondary (MEDIUM, non-blocking).

Both are `drift`/`version_secondary` → capped MEDIUM (advisory, never FAIL).
