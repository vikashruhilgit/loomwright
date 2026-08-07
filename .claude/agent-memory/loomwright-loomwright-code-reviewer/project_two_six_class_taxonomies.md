---
name: two-six-class-taxonomies
description: Repo has TWO distinct six-class taxonomies; CHANGELOG/banner prose frequently conflates them
metadata:
  type: project
---

The repo has **two separate six-class taxonomies** that are easy to conflate in release-note prose:

1. **`/pr-postmortem` review-round buckets** (`skills/pr-postmortem/SKILL.md:33-38`): `plan_gap`, `missing_context`, `convention_mismatch`, `execution_bug`, `quality_gap`, `scope_too_large` — classifies *why a review round happened*.
2. **Self-Heal Miss-Class Checklist** (`skills/quality-checklist/SKILL.md`): validation parity, numeric falsy coercion, positional-args-vs-options-object, branch coverage, count/version/restated-list drift, cross-reference precision drift — the repo-agnostic *behavioral/doc miss-classes* the self-heal lens + CI prompt apply.

**Why:** v14.29.0 R4 added the *Self-Heal Miss-Class Checklist* (NOT the postmortem buckets) to `.github/workflows/claude-code-review.yml`, but CHANGELOG.md:7 described it as "the same taxonomy /pr-postmortem already buckets into" and listed the postmortem class names — a restated-list drift caught in review (PR #62, v14.29.0). Both are "six classes," so prose slips between them.

**How to apply:** When reviewing any release that touches the CI review prompt, self-heal lens, or postmortem skill, verify the *named class list* in release notes (CHANGELOG/CLAUDE.md banners) matches the taxonomy actually edited in code. The roadmap R4 intent (`LEARNING_LOOP_ROADMAP.md:226`) is "mirror local review/self-heal vocabulary" = the checklist. Note: this is a secondary-doc-surface drift (capped MEDIUM, never FAILs) — report, don't gate. See [[half-fixed-example-classes]].
