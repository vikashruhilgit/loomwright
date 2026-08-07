---
name: insights-per-run-frontmatter-gap
description: build-insights.sh per-run note frontmatter omits fields the insights.md doc lists; doc sweeps overclaim per-run YAML
metadata:
  type: project
---

`commands/insights.md` step 3 enumerates the per-run note YAML frontmatter fields, but `scripts/build-insights.sh`'s per-run frontmatter loop (the `jq -r` block around L75-92) is a SEPARATE hand-maintained list from the aggregate record builder (L48-66). A field added to the record + aggregate table is NOT automatically in the per-run frontmatter.

**Why:** v14.24.0 added `plugin_version` to the record (L53) and the per-version aggregate table, and insights.md step 3 was updated to claim per-run notes carry `plugin_version` — but the per-run frontmatter loop was never updated, so the per-run note omits it. test-insights.sh only asserts the aggregate table, never per-run frontmatter, so CI passes.

**How to apply:** When auditing any change that adds a session_end/run field + touches insights.md, grep the per-run frontmatter `jq` block in build-insights.sh for the field name. If insights.md step 3 lists it but the per-run loop doesn't emit it, that's `drift`/`workflow` (MEDIUM — advisory dashboard, nothing breaks). Cross-ref [[half-fixed-example-classes]].
