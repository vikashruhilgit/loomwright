# `.agent/rules/` — committed house rules

This directory is the repo's **single, version-controlled source of truth for project conventions** ("house rules"). Unlike `.supervisor/` (gitignored, per-user runtime state), **`.agent/rules/` is committed and travels with the repo** — so a rule you author here is visible to every clone, every teammate, and every agent that reads it.

> **Protocol authority:** `ai-agent-manager-plugin/skills/rules/SKILL.md`. The schema below is a summary; the skill governs validation, the reader contract, the scan-to-suggest spec, the `/rules add` write discipline, and the `check` trust boundary. On any conflict, the skill wins.

## Layout

- `.agent/rules/` holds **zero-or-more `*.json` files**.
- Each `*.json` file is a **JSON ARRAY of rule objects** (never a bare object — the reader and `/rules add` both require an array).
- The files are globbed and merged by `ai-agent-manager-plugin/scripts/read-rules.sh` in `LC_ALL=C` repo-relative-path-sorted order; within a file, by array index. The **first valid occurrence of a rule `id` wins**.

## Rule schema

Each rule object:

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | UNIQUE across the merged set of all `*.json` files. |
| `category` | string | yes | The convention's category; also drives the target filename for `/rules add` (slugified to `[a-z0-9-]`). |
| `statement` | string | yes | The human-readable rule text. |
| `enforcement` | `"advisory"` \| `"must"` | yes | Exactly one of these two values. |
| `check` | string \| null | yes | A runnable shell string OR `null`. **Read as DATA only — `read-rules.sh` NEVER executes it.** `/rules check` runs a `must`-rule's `check` ONLY when human-invoked and explicitly confirmed. |
| `provenance` | object | yes | e.g. `{ "source": "...", "added": "<UTC ISO-8601>" }`. |
| `applies_to` | path-glob / language / category | no (optional) | **RESERVED for a future slice (3b-ii) enforcement filtering — NOT consulted by the v1 reader.** Forward-compat only. |

An object that is missing a required field, carries an unknown `enforcement` value, or duplicates an already-seen `id` is **skipped** (not emitted) — the reader never crashes and still emits the remaining valid rules.

## Example

`example.json` is shown here for illustration only (this plugin's own repo ships NO populated live rules — see below). A valid file looks like:

```json
[
  {
    "id": "version-validate-version-script-must-pass",
    "category": "version",
    "statement": "scripts/validate-version.sh must exit 0 before a version bump lands.",
    "enforcement": "must",
    "check": "bash scripts/validate-version.sh",
    "provenance": { "source": "/rules add", "added": "2026-06-30T12:00:00Z" }
  }
]
```

## This repo ships the README/schema, NOT live rules

This plugin's own repository ships **only this README (the schema + example)** — there are **no populated live `*.json` rules** in `.agent/rules/` here. Authoring rules is **opt-in** via the `/rules` command:

- `/rules list` — show the applicable rules (calls `read-rules.sh`).
- `/rules suggest` — scan the repo and PROPOSE rules (human-confirmed, never auto-writes).
- `/rules add` — author a rule (confirm-only, append-only, path-contained atomic write).
- `/rules check` — run `must`-rule checks (human-invoked, confirmed only — never an unattended gate).
