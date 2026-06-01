---
description: On-demand scan for newly-available Claude Code features / dependency updates the plugin could adopt — proposes candidates, never self-applies
---

> **Read-only / propose-only contract.** `/capability-check` is strictly read-only on the plugin and the codebase. It fetches the live Claude Code changelog/docs and dependency info, diffs them against the tracked capability baseline, and **reports candidate adoptions**. It **never** edits an agent, command, skill, hook, or any plugin file. Adoption is always a separate, human-driven change (typically a `/launch-pad` → `/supervisor` run). The only file it may write is the baseline itself, and only when you pass `--update-baseline`.

# Command: /capability-check

## Purpose

The plugin can quietly fall behind Claude Code: a new hook event, tool, agent-frontmatter field, or SDK feature ships, and nothing prompts the maintainer to adopt it. `/capability-check` is the **on-demand** answer (the "continuously checks what's available" half of self-evolution, built abandonment-resilient — you run it when a session surfaces a gap, instead of being trained to ignore a weekly cron).

It does what a maintainer would do by hand: read what's new in Claude Code, compare it to what this plugin already uses (the **baseline**), and surface a short, actionable list of things worth adopting — each as a *candidate*, never an applied change.

## Usage

```bash
/capability-check                      # scan, print a report of candidate adoptions
/capability-check --max-fetches 3      # tighten the network budget (default 5)
/capability-check --update-baseline    # after reviewing, record this scan as the new baseline (maintainer / repo-root only)
/capability-check --save               # also write the report to .supervisor/capability/{date}.md (gitignored)
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--max-fetches N` | `5` | Hard cap on external fetches (WebFetch + Context7 calls) for the run. Bounds cost; a run that hits the cap reports partial coverage and says so. |
| `--update-baseline` | off | After you've reviewed the report, rewrite `docs/CAPABILITY_BASELINE.json` with the current scan date + any features you've now accounted for. Meaningful only in the plugin's own repo (the install dir is read-only); a no-op notice elsewhere. |
| `--save` | off | Also persist the report to `.supervisor/capability/{YYYY-MM-DD}.md` (gitignored). Default is print-only. |

## Workflow (bounded, on-demand)

```
LOAD baseline → FETCH live state (≤ max-fetches) → DIFF → REPORT candidates (or suppress) → [optional] UPDATE baseline
```

### 1. LOAD baseline
Read `${CLAUDE_PLUGIN_ROOT}/docs/CAPABILITY_BASELINE.json` — the snapshot of Claude Code features the plugin already uses (`claude_code.*` lists), features deliberately **not** adopted yet (`known_not_adopted`, so they aren't re-flagged), pinned `deps`, and the `sources_to_check` URLs. If the file is missing or unparseable, report that and stop (do not invent a baseline).

### 2. FETCH live state (hard-bounded)
Spend **at most `--max-fetches`** external calls, in priority order, stopping when the budget is hit:
1. WebFetch `sources_to_check.claude_code_changelog` — the release notes.
2. WebFetch `sources_to_check.claude_code_docs_hooks` and `…_docs_subagents` — to spot new hook events / agent-frontmatter fields / tools.
3. For each entry in `deps` with a real package: Context7 `resolve-library-id` + a short `query-docs` for "latest version / breaking changes" (skip unpinned/bundled ones where it adds no signal).
4. If a primary fetch fails, fall back to **one** WebSearch using `sources_to_check.search_fallback`.

If the budget is exhausted before all sources are covered, continue to REPORT but mark coverage as **partial** and list which sources were not checked. Never exceed the cap.

### 3. DIFF
From the fetched material, identify items **present upstream but absent from the baseline** and not already in `known_not_adopted`:
- new **hook events** or hook capabilities,
- new **tools** or tool options,
- new **agent-frontmatter fields** / subagent features,
- new **SDK / slash-command / skill / MCP** capabilities,
- **dependency** updates with relevant changes.

For each, write one line of *why it matters for THIS plugin* — which agent/hook/command it would plausibly improve. Discard anything the plugin already uses or has explicitly deferred.

### 4. REPORT (rare + actionable)
- **If there are no new candidates:** print exactly one line — `No new Claude Code capabilities since baseline {baseline_date} (checked {N} sources). Nothing to adopt.` — and stop. **Do not pad** the output. (Red-team W3: a report that fires every run with already-known facts trains the maintainer to ignore it.)
- **If there are candidates:** print a `CAPABILITY_REPORT` with, per candidate:
  - **Capability** — name + one-line description of what shipped.
  - **Source** — the URL/version it came from.
  - **Plugin fit** — the specific agent/hook/command/skill it would improve, and a rough effort (S/M/L).
  - **Status: CANDIDATE — not applied.** Adoption is a separate human-driven change.
  - A coverage footer (sources checked / skipped, partial?).
- With `--save`, also write the same report to `.supervisor/capability/{YYYY-MM-DD}.md`.

**Never** edit an agent/command/skill/hook/manifest here. The report is the deliverable; adopting a candidate is a deliberate follow-up (usually `/launch-pad goal: "adopt <capability>"` → `/supervisor`).

### 5. UPDATE baseline (only with `--update-baseline`)
After you've read the report and decided what's accounted for, rewrite `docs/CAPABILITY_BASELINE.json`: bump `baseline_date` to today, add adopted capabilities to the relevant `claude_code.*` lists, and move "seen but not adopting yet" items into `known_not_adopted` (so the next run doesn't re-flag them). This is a maintainer action in the plugin's own repo; in an installed copy the plugin dir is read-only, so print a notice and skip the write.

## Guardrails (non-negotiable)
- **Never self-applies.** The plugin may *propose* changes to its own agents/hooks/gates; a human applies them. This command only reads + reports (and writes the baseline only on explicit `--update-baseline`).
- **Bounded.** Hard `--max-fetches` cap; no unbounded crawling.
- **Human-gated + rare.** Suppress no-change output; surface only actionable candidates.
- **Advisory.** Candidates are suggestions, not obligations — subordinate to the maintainer's judgment.

## See Also
- `docs/CAPABILITY_BASELINE.json` — the tracked baseline this command diffs against.
- `docs/SPIKES/ENHANCEMENT_PLAN_v15_DRAFT.md` §4 — self-evolution design (on-demand first; scheduled scanner is deferred P5 behind four guardrails).
- `commands/launch-pad.md` / `commands/supervisor.md` — how to actually adopt a reviewed candidate.
- `commands/dreaming.md` — the inward-looking counterpart (learns from past runs); `/capability-check` is the outward-looking one (learns what Claude Code newly offers).
