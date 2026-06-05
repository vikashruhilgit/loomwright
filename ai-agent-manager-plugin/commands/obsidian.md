---
description: Project this repo's accumulated knowledge (runs, Twin contracts, lessons, project memory) into a local, fully-linked Obsidian vault — read-only one-way projection, no data leaves your machine
---

> **Read-only downstream projection — writes only to a vault you choose.** `/obsidian` READS the artifacts the plugin already wrote (`.supervisor/twin/`, `.supervisor/logs/`, `.supervisor/memory/`) and WRITES only into an external Obsidian vault you configure. It modifies **no** source-of-truth file — no agent, no `/insights`, no `build-insights.sh`, no `supervisor.md`, no `.supervisor/` source — **no agent ever reads the vault back**, and **no data leaves your machine** (it writes local markdown to a local vault directory you chose). The engine behaves identically with or without the vault.

# Command: /obsidian

## Purpose

The plugin accumulates real knowledge across runs — **session logs** (work/quality/Twin hard signals), **System Twin contracts** (per-subsystem dependency graphs), and **lessons / project memory** — but it lives as scattered `.supervisor/` artifacts. `/obsidian` projects all of it into a single, fully-**linked** Obsidian vault: an index/MOC note, one note per run, Twin-contract notes wired together with `[[dependency]]` wikilinks (so Obsidian's **graph view = blast radius**), and Lessons / Project-Memory notes when present. It is a **one-way, read-only projection for human/Obsidian consumption** — never a source of truth.

## Usage

```bash
/obsidian
```

## Opt-in / configuration

`/obsidian` does **nothing** unless you tell it where your vault lives. Configure the destination via **either**:

- **Environment variable** — `AI_AGENT_MANAGER_OBSIDIAN_VAULT="$HOME/Obsidian/MyVault"`, or
- **Config file** — `.supervisor/obsidian-config.json`:
  ```json
  { "vault": "/absolute/path/to/your/Obsidian/Vault", "slug": "optional-project-name" }
  ```

The **slug** (per-project subfolder name) resolves in this order: `AI_AGENT_MANAGER_OBSIDIAN_SLUG` env var → `.slug` in the config file → **default = the repo's directory name**. The slug is sanitized to a filesystem-safe token (path separators and anything outside `[A-Za-z0-9._-]` collapse to `-`), so a project can never write outside its own subfolder.

The vault is a **shared destination** — multiple projects coexist under one vault, each in its own `<vault>/<slug>/` subfolder. The script only ever writes under that subfolder.

**No-op when unset:** if no vault is configured, `/obsidian` writes nothing, prints exactly how to opt in (env var or config file), and **exits 0**. It never fails its caller.

## What it does

Runs the deterministic projection and reports where it wrote:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-vault.sh"
```

It produces a per-project subfolder `<vault>/<slug>/` containing:

1. **`<slug> — Index.md`** — the index / map-of-content note: links to every run, every Twin contract, and the Lessons / Project-Memory notes, plus a **Dataview** live-board snippet (`FROM #project/<slug> AND #type/session-log`) so the runs render as a sortable table.
2. **`<slug> — Run — <session_id>.md`** — one note per run, derived from each log's last `session_end` event, with YAML frontmatter (`status`, `rubric_score`, `heal_iterations`, `subtasks_completed`, `files_changed`, `pr_url`, and when present the System Twin hard-signal fields `contract_conformance_status`, `contract_violations`, `benchmark_status`/`metric`/`value`/`delta`). When a run reports conformance and contract notes exist, it cross-links to them so the graph connects runs to the subsystems they touched.
3. **`<slug> — Contract — <id>.md`** — one note per System Twin contract (`.supervisor/twin/contracts/*.md`), with the dependencies surfaced as `[[<slug> — Contract — <dep>]]` **wikilinks** under a "Depends on (blast radius)" section. In Obsidian's graph view this renders the dependency graph directly — the **blast radius** of any subsystem.
4. **`<slug> — Lessons.md`** and **`<slug> — Project Memory.md`** — projected from `.supervisor/memory/LESSONS.md` and `.supervisor/memory/PROJECT_MEMORY.md` when those files exist (advisory; subordinate to CLAUDE.md).

**Content-hash idempotent:** each run fully re-derives the vault and writes a note only when its content hash differs from the on-disk file. The hashed body carries no per-run timestamp, so **re-running with no source change writes zero notes**.

**Sparse-tolerant:** any source can be absent (no Twin dir, no logs, no lessons, no project memory) and the script still emits a **valid vault** with the missing section omitted or near-empty, and **always exits 0**.

## View in Obsidian (optional)

The output is plain markdown — readable in any editor or on GitHub. To get the *linked* experience, open the configured vault in **Obsidian** and install the **Dataview** plugin: the index's live board renders as a sortable table of runs, and the **graph view** visualizes the `[[dependency]]` wikilinks between Twin contracts as your blast-radius map. Obsidian is purely the optional viewer — the value is the generated, linked markdown.

## See Also
- `commands/insights.md` — the local, in-repo insights dashboard (`.supervisor/insights/`); `/obsidian` is the external, fully-linked vault projection of the same (and more) artifacts.
- `scripts/build-vault.sh` — the deterministic, read-only projection engine (jq + content-hash dedup).
- `scripts/test-build-vault.sh` — its self-test.
