---
description: Generate a local, Obsidian-friendly insights dashboard (work · quality · session performance) from the plugin's session logs — read-only, no data leaves your machine
---

> **Read-only on your work; writes only a derived report.** `/insights` reads the session logs the plugin already wrote (`.supervisor/logs/*.jsonl`) and writes a derived dashboard to `.supervisor/insights/` (gitignored). It touches no code, no agent, no state, and sends nothing anywhere. It does **not** compute token/dollar **cost** — that data lives in Claude Code's own transcripts, not here (see the Cost note below).

# Command: /insights

## Purpose

The plugin already records rich **work**, **quality**, and **session-performance** signals per run — completion status, self-heal outcome/iterations, rubric scores, subtasks completed, files changed, PR links — but there's no way to *see* them. `/insights` rolls those logs up into a single markdown dashboard plus one note per run, with **Dataview-compatible frontmatter** so the same files render as a live, sortable board if you open `.supervisor/` in Obsidian (and as plain markdown tables everywhere else).

## Usage

```bash
/insights
```

## What it does

Runs the deterministic aggregator and reports where it wrote:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-insights.sh"
```

1. Reads every `.supervisor/logs/*.jsonl`, takes each run's `session_end` event (tolerant of older logs with fewer fields), and computes the aggregates with `jq` (real numbers, not estimates).
2. Writes **`.supervisor/insights/dashboard.md`** — Summary (sessions, completed/failed, completion rate, self-heal PASS count, avg heal iterations, total subtasks/files), a Recent-sessions table, a Cost note, and an Obsidian/Dataview snippet.
3. Writes **`.supervisor/insights/runs/<session_id>.md`** — one note per run with YAML frontmatter (`status`, `rubric_score`, `heal_iterations`, `subtasks_completed`, `files_changed`, `pr_url`, …).

If there are no logs yet, it says so and writes nothing. Re-run any time to refresh.

## Cost (tokens / $)

**Not captured by this plugin** — by design it records *what work was done and how well*, not *how many tokens it cost*. Token/$ usage lives in Claude Code's own transcripts (`~/.claude/projects/`). For real figures use:

```bash
npx ccusage@latest            # daily token/$ table
npx ccusage@latest session    # per-session breakdown
```

…or Claude Code's built-in `/cost`. The dashboard shows an explicit "not captured" stub rather than faking numbers.

## View in Obsidian (optional)

The output is plain markdown — open it in any editor or on GitHub. To get a *live dashboard*: point an Obsidian vault at `.supervisor/` (or symlink `.supervisor/insights` into a vault) and install the **Dataview** plugin. Then a note like:

````markdown
```dataview
TABLE status, rubric_score, heal_iterations, files_changed, pr_url
FROM "insights/runs"
SORT created DESC
```
````

…renders as a sortable, always-current board of every run. Obsidian is purely the optional viewer — the value is the generated markdown.

## See Also
- `scripts/build-insights.sh` — the deterministic aggregator (jq); `scripts/test-insights.sh` — its self-test.
- `commands/telemetry.md` — the opt-in counterpart that *sends* a scored summary to GitHub Issues; `/insights` is the local, private, visual view.
- `commands/dreaming.md` — learns from past runs (inward); `commands/capability-check.md` — scans new Claude Code features (outward); `/insights` *measures* the runs.
