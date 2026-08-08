---
name: attack-user-global-config-writes
description: Writes to ~/.claude/settings.json are the highest blast-radius op — MUST deep-merge + timestamped-backup-first + abort-on-parse-failure
metadata:
  type: project
---

Writes to user-global files (`~/.claude/settings.json`) are the highest blast-radius op in the plugin — a bad merge corrupts every project for the user.

**Why:** `/setup observability` jq-deep-merges an 8-key env block into the user's global settings.

**How to apply:** Any settings/config write MUST jq-deep-merge (preserve existing keys), write a timestamped backup FIRST, and ABORT (never half-write) on parse failure. Flag any overwrite, missing backup, or write-after-parse-failure as FATAL.
