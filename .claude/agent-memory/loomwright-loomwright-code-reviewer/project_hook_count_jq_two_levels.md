---
name: hook-count-jq-two-levels
description: Counting hooks.json leaf entries needs a TWO-level descent; the obvious one-level jq undercounts
metadata:
  type: project
---
hooks.json has a THREE-level nest: `.hooks.<Event>[]` are matcher-objects, each
carrying its own `.hooks[]` array of leaf command/prompt entries. The canonical
count (claimed as "20 hooks" in CLAUDE.md/docs/marketplace) is the sum of LEAF
entries, NOT matcher-objects.

**Why:** `jq '[.hooks[][]] | length'` counts matcher-objects (gave 15) and silently
undercounts — it looks plausible and you can wrongly flag a count drift.

**How to apply:** count with `jq '[.hooks[][] | .hooks[]] | length'` (descends into
each matcher's own `.hooks[]`). SubagentStop alone holds 7 matcher-objects; total
matcher-objects=15, total leaf entries=20. The doc-currency gate uses the leaf-entry
rule, so reconcile against 20.
