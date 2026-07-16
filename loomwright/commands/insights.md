---
description: Generate a local, Obsidian-friendly insights dashboard (work · quality · session performance) from the plugin's session logs — read-only, no data leaves your machine
---

> **Read-only on your work; writes only a derived report.** `/insights` reads the session logs the plugin already wrote (`.supervisor/logs/*.jsonl`) and writes a derived dashboard to `.supervisor/insights/` (gitignored). It touches no code, no agent, no state, and sends nothing anywhere. It does **not** compute token/dollar **billing cost** — that data lives in Claude Code's own transcripts (see the Cost note / `ccusage`). Separately it may roll up an advisory **Token economics** section from additive `token_ledger` events (real usage vs transcript-byte proxy) when those lines exist.

# Command: /insights

> **This is the plugin's deterministic _run scoreboard_** — it measures *this plugin's own runs* (work, quality, session performance, eval pass-rate, System Twin growth) from the logs it writes, computed with jq. For whole-usage **coaching** across all your Claude Code work, use **Claude Code Insights** (the built-in feature); for token/$ **billing cost**, use **`ccusage`** (see the Cost note below). The dashboard's **Token economics** section is a separate advisory ledger/proxy rollup from `token_ledger` events — not a substitute for ccusage. `/insights` is distinct from, not a replacement for, either.

## Purpose

The plugin already records rich **work**, **quality**, and **session-performance** signals per run — completion status, self-heal outcome/iterations, rubric scores, subtasks completed, files changed, PR links, the additive **`plugin_version`** stamp (`"unknown"` for older logs), and (when present) the **System Twin hard signal** (contract-conformance status + violations, benchmark status/value/delta) — but there's no way to *see* them. `/insights` rolls those logs up into a single markdown dashboard plus one note per run, with **Dataview-compatible frontmatter** so the same files render as a live, sortable board if you open `.supervisor/` in Obsidian (and as plain markdown tables everywhere else).

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
2. Writes **`.supervisor/insights/dashboard.md`** — Summary (sessions, completed/failed, completion rate, self-heal PASS count, avg heal iterations, total subtasks/files), an optional **System Twin hard-signal** section (contract-conformance + benchmark trend; see below), a **Per-version insights** section (runs / heal-PASS rate / avg heal iterations / avg rubric score, grouped by the additive `plugin_version` stamp; see below), a **Knowledge sources** section (which memory sources runs reported consulting; suppressed when none; see below), an **Eval fitness function** section, a **Heal-signal catch-rate (MEASURE)** section (the self-heal confusion-matrix trend; suppressed when no data; see below), a **System Twin growth** section, a Cost note (ccusage $), an advisory **Token economics** section (`token_ledger` real vs proxy), a Recent-sessions table (with a Twin conformance/Δ column), a **Corpus health** section, and an Obsidian/Dataview snippet.
3. Writes **`.supervisor/insights/runs/<session_id>.md`** — one note per run with YAML frontmatter (`status`, `rubric_score`, `heal_iterations`, `subtasks_completed`, `files_changed`, `pr_url`, `plugin_version` (`"unknown"` for older logs), and when present `contract_conformance_status`, `contract_violations`, `benchmark_status`, `benchmark_value`, `benchmark_delta`, …).

### System Twin hard-signal trend

When runs carry them, `/insights` also surfaces the **System Twin hard signal** sourced from the *same* `session_end` events — the six flat fields `contract_conformance_status`, `contract_violations`, `benchmark_status`, `benchmark_metric`, `benchmark_value`, `benchmark_delta`. The dashboard aggregates them into a dedicated section: runs reporting conformance, conformance-pass count, total (advisory) contract violations, benchmark regressed/improved counts, and the latest benchmark value/delta — so you can watch **contract-conformance and benchmark delta over time**.

This is **advisory only** — it never blocks a PR or changes a heal decision — and **tolerant of older logs**: runs that predate these fields are simply omitted from the hard-signal counts, and if *no* run reports them the section is suppressed entirely (no fabricated zeros), so the dashboard renders unchanged.

### Eval fitness function + System Twin growth

Two sections that are **always rendered** whenever a dashboard is written (unlike the optional hard-signal section, which is suppressed when absent):

- **Eval fitness function** — the deterministic eval-corpus pass-rate, sourced from `.supervisor/eval/results.jsonl` (written by `scripts/run-eval.sh`). Shows the **latest pass-rate** (e.g. `6/6`) and a **trend** oldest → newest (e.g. `4/4 → 5/6 → 6/6`), bounded to the most recent ~10 points. When no eval runs have been recorded yet, it shows a benign "no data yet" line.
- **System Twin growth** — how the contract store has grown, sourced from `.supervisor/twin/contracts/*.md` and `.supervisor/twin/.provenance.jsonl`. Shows the current **contract count** (live `*.md` files) and a **cumulative count of `add` events** grouped by date, oldest → newest (e.g. `10 contracts (2 → 4 → 12)`), bounded to ~8 points. The trend counts append-only `add` provenance events, so it can **exceed** the current contract count when contracts are re-added or updated over time (12 add-events vs 10 current files in that example). When the twin store is missing/empty it shows a benign "no data yet" line.

Both are advisory and computed with jq (never guessed); both degrade gracefully (the script always exits 0).

### Heal-signal catch-rate (MEASURE leg)

A section that surfaces **how well the self-heal pass actually catches problems** on this repo's own PR history — the MEASURE leg of the Local Twin path (`docs/SPIKES/LOCAL_TWIN_PATH.md`). It is sourced from `.supervisor/heal-signal/results.jsonl`, an append-only trend ledger written by **`scripts/measure-heal-signal.sh`** (the re-runnable, READ-ONLY self-heal confusion-matrix instrument — harvests the heal signal from done-brief `## Outcome` blocks, joins it to the `/pr-postmortem` churn labels, and emits a recall / false-positive / false-negative matrix). The dashboard shows the **latest catch-rate (recall)**, **false-negatives / N**, **coverage** (share of heal-signal PRs that carry a model-classified label), **self-heal-lane churn share**, and a **catch-rate trend** oldest → newest (bounded ~10 points).

Because the labels are **churn** (`/pr-postmortem`), these numbers are **advisory / DIRECTIONAL** — they never gate a PR or change a heal decision. Like the System-Twin-hard-signal and Knowledge-sources sections, it is **suppressed entirely when no scored matrix exists** (no `results.jsonl`, or only unscored `n=0` records) — no fabricated zeros. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/measure-heal-signal.sh"` to refresh the ledger (each run appends one trend point); pass `--backfill N` to print a bounded plan for raising coverage (it never auto-dispatches `/pr-postmortem`).

### Per-version insights

A dedicated table groups `session_end` events by the **additive `plugin_version` stamp** (recorded since v14.24.0; events from older logs that lack the field group under `"unknown"`). One row per version, newest first: **runs**, **heal-PASS rate**, **avg heal iterations** (across runs that report `heal_iterations`), and **avg rubric score** (each `"M/N"` parsed to a percentage; `—` when no run carries one). This makes quality regressions/improvements visible **release-over-release** — e.g. a heal-PASS rate that drops after a version bump points at that release. Advisory only, computed with jq, tolerant of mixed-version logs.

### Knowledge sources

A dedicated section surfaces the additive **`knowledge_sources_used`** array from the *same* `session_end` events (emitted since v14.28.0) — the flat, lowercase set of memory sources a run reported actually consulting (open set: `project_memory`, `lessons:<category>`, `agent_memory:<agent>`, `twin:<path>`, `brain_context`). The dashboard reports the **count of runs reporting a source** (e.g. `2 of 3`), a **Top source tags** table (each tag by frequency, descending), and a **Per-version usage** table (runs-with-a-source grouped by `plugin_version`, newest first). This is the Phase 2 "memory APPLY" signal — it distinguishes *memory existed* from *memory was actually used*. Advisory only (never blocks a PR or changes a heal decision), computed with jq, and **tolerant of older logs**: runs without the field count as none, and if *no* run reports any source the section is suppressed entirely (no fabricated zeros, mirroring the hard-signal section).

If there are no logs yet, it says so and writes nothing. Re-run any time to refresh.

## Cost (tokens / $)

**Dollar / billing cost is not captured by this plugin** — by design it records *what work was done and how well*, not *how many dollars it cost*. Token/$ billing figures live in Claude Code's own transcripts (`~/.claude/projects/`). For real figures use:

```bash
npx ccusage@latest            # daily token/$ table
npx ccusage@latest session    # per-session breakdown
```

…or Claude Code's built-in `/cost`. The dashboard shows an explicit Cost stub pointing at `ccusage` rather than faking dollar amounts.

## Token economics

An **advisory** section (always rendered when a dashboard is written; never gates) that rolls up additive `"event":"token_ledger"` lines from `.supervisor/logs/*.jsonl` (emitted by `scripts/emit-token-ledger.sh` on SubagentStop telemetry hooks — see `docs/TELEMETRY.md` §Token ledger). It is **separate from Cost / ccusage**:

- **Real usage** (`proxy: false`) — when usage/token fields are present; per-`agent_type` input/output totals. A **cache-hit ratio** is shown only when real cache fields (`cache_read_input_tokens` / `cache_creation_input_tokens`, top-level or under `usage`) exist; otherwise that line is omitted.
- **Transcript-byte proxy** (`proxy: true`, `token_proxy_kind: transcript_bytes`) — byte counts of agent transcripts, **explicitly labelled as a proxy and never as tokens** (the expected path today when SubagentStop lacks usage).
- **Absent / malformed** — heading + a short degrade note when no ledger lines exist (Corpus health style); malformed JSONL lines are skipped per-line; the script always exits 0.

Reserved future key `graph_context_used` is ignored by this reader (emitters must not write it yet).

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
- `scripts/measure-heal-signal.{sh,py}` — the READ-ONLY self-heal catch-rate instrument feeding the **Heal-signal catch-rate (MEASURE)** section (`scripts/test-measure-heal-signal.sh` — its self-test).
- `commands/telemetry.md` — the opt-in counterpart that *sends* a scored summary to GitHub Issues; `/insights` is the local, private, visual view.
- `commands/dreaming.md` — learns from past runs (inward); `commands/capability-check.md` — scans new Claude Code features (outward); `/insights` *measures* the runs.
