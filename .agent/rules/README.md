# `.agent/rules/` — committed house rules

This directory is the repo's **single, version-controlled source of truth for project conventions** ("house rules"). Unlike `.supervisor/` (gitignored, per-user runtime state), **`.agent/rules/` is committed and travels with the repo** — so a rule you author here is visible to every clone, every teammate, and every agent that reads it.

> **Protocol authority:** `loomwright/skills/rules/SKILL.md`. The schema below is a summary; the skill governs validation, the reader contract, the scan-to-suggest spec, the `/rules add` write discipline, and the `check` trust boundary. On any conflict, the skill wins.

## Layout

- `.agent/rules/` holds **zero-or-more `*.json` files**.
- Each `*.json` file is a **JSON ARRAY of rule objects** (never a bare object — the reader and `/rules add` both require an array).
- The files are globbed and merged by `loomwright/scripts/read-rules.sh` in `LC_ALL=C` repo-relative-path-sorted order; within a file, by array index. The **first valid occurrence of a rule `id` wins**.

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
| `applies_to` | `null` \| array of path globs | no (optional) | **ACTIVE path routing.** `null` or absent ⇒ the rule is **repo-wide**. A non-empty **array of strings** ⇒ the rule is emitted only when a touched path passed to `read-rules.sh` matches one of its globs. Any other shape fails **OPEN** (emitted repo-wide + a diagnostic). See "Path routing" below. |

An object that is missing a required field, carries an unknown `enforcement` value, or duplicates an already-seen `id` is **skipped** (not emitted) — the reader never crashes and still emits the remaining valid rules.

## Path routing (`applies_to`)

`read-rules.sh` takes the touched paths as **positional arguments** and uses them as a real filter:

```bash
bash loomwright/scripts/read-rules.sh loomwright/scripts/x.sh docs/guide.md   # scoped
bash loomwright/scripts/read-rules.sh                                          # repo-wide (no args)
```

- `applies_to: null` or the key absent ⇒ the rule is **repo-wide** and always emitted. This is the default and what `/rules add` writes when you do not pass `--applies-to`.
- A **non-empty array of strings** ⇒ the rule is emitted only when **some** supplied path matches **some** pattern.
- Everything ambiguous **fails OPEN** — the rule is emitted repo-wide anyway, with a one-line diagnostic to stderr and `.supervisor/logs/memory.log` (never to stdout): a non-array value, an array containing a non-string, an empty array, **and a call with no path arguments at all**. Under-scoping shows a rule that did not need showing; over-scoping silently hides a convention.
- Supersession is resolved **before** routing, so a rule routed out of a given call never resurrects the rule it supersedes.

### Pattern syntax — bash `case` globs, **not** `.gitignore`

| | `case`-glob (used here) | `.gitignore` (what you may expect) |
|---|---|---|
| `*` | matches any characters, **including `/`** | stops at `/` |
| `**` | **identical to `*`** — no special meaning | "any number of directories" |
| Anchoring | matched against the **whole** path, so anchored at both ends | leading `/` anchors to the repo root |
| `!pattern` | **not supported** — `!` is a literal character | re-includes an excluded path |

So `"loomwright/scripts/*"` **does** match `loomwright/scripts/a/b/c.sh`, `"*.md"` matches `docs/a/b/c.md` as well as `README.md`, and `"docs"` matches only the literal path `docs` (use `"docs/*"` for the subtree). Touched paths arrive **repo-relative**, which is why `/rules add --applies-to` rejects `..`-bearing, absolute (`/…`) and home-relative (`~…`) patterns at write time — they could only ever match nothing. Full contract: `loomwright/skills/rules/SKILL.md` §1 and §3.

## Example

The example below is shown for illustration only (this plugin's own repo ships NO populated live rules — see below; there is no `example.json` file on disk). A valid rule file looks like:

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

- `/rules list` — show the applicable rules (calls `read-rules.sh` with no path args, i.e. repo-wide).
- `/rules suggest` — scan the repo and PROPOSE rules (human-confirmed, never auto-writes).
- `/rules add` — author a rule (confirm-only, append-only, path-contained atomic write). `--applies-to <glob>` is repeatable and sets the routing scope; omit it for a repo-wide rule.
- `/rules check` — run `must`-rule checks (human-invoked, confirmed only — never an unattended gate).
