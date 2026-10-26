---
description: One read-only report of everything the plugin left running or lying around — processes, run locks, lanes, worktrees and branches, stale run state, plus report-only plugin-adjacent and not-the-plugin's rows — each with a suggested action; acts only on the rows the owner picks, each through its guarded helper after a re-check
---

> **Read-only, except the rows the owner picks.** `/janitor` prints the report and changes nothing. Only after the owner answers the `JAN-ACT` question does it run `act --confirm` on exactly the picked rows. Every action runs through its existing guarded helper after a fresh re-check. It never merges, never pushes, and never acts on a row it was not given.

# Command: /janitor

## Purpose

Background processes and leftovers are tracked by separate mechanisms: the process registry, run locks, lane tables, merge-watch markers, config backups and sweep verdicts. Nothing shows them together. `/janitor` lists each item once with its owner, age, state, evidence and a suggested action with the reason. A stray process is stopped only when the owner picks it, and only after its start time and command line are re-checked.

## Usage

```bash
/janitor                 # the report, then the owner question (interactive sessions only)
/janitor --report        # the report only; never asks, never acts
/janitor --json          # the report as ONE JSON object; never asks, never acts
/janitor --non-interactive   # same as --report
```

## What it does

Every script named on this page lives in the plugin's `scripts/` directory and runs as `bash "${CLAUDE_PLUGIN_ROOT}/scripts/<script>" …`. The report, its groups, row fields, row ids, the closed action set and every executor are defined once, in the header of `scripts/janitor-report.sh`. This page only renders the report and asks.

1. **Report.** Run `janitor-report.sh` (`--json` for `/janitor --json`) and print its output as is. The groups are processes, run locks, lanes, worktrees and branches, stale run state, plugin-adjacent (report only) and not the plugin's (report only). A reader that fails shows as an `unknown` row, never as a clean group.
2. **Can't-ask check.** The flow cannot ask under `--report`, `--json` or `--non-interactive`, in a headless print-mode session, or when this prose runs inside a subagent (the host strips the ask tool there). In that case stop after step 1 and print `janitor: report only — nothing acted on`. Exit 0. Never pick a row for the owner, and never run `act`.
3. **Ask once.** If the summary line shows `0 actionable`, stop. Otherwise ask ONE multi-select question with `header: "JAN-ACT"`. The options are the actionable rows (any action but `none`), grouped by group, each labelled `<id> — <what> (<action>)`, and nothing is pre-selected. Every `sweep-apply` row is labelled `apply the whole sweep (<n> rows)`, because the sweep has no per-path filter; its id changes whenever that set does. A `reap` row whose reason names a `live host session` is labelled `<id> — <what> (reap — ENDS A LIVE HOST SESSION)`. A lock row with `alt: force-unlock` is offered as `<id> — force-unlock <checkout> (asks again)`. When the rows do not fit the ask tool's option limit, offer one option per action (`reap — <n> rows`, …), list every row id in the question text, and accept row ids typed in the free-text answer. An empty answer means nothing is acted on.
4. **Second confirmation for force-unlock.** For each picked force-unlock row, ask again with `header: "JAN-ACT"`: name the checkout, the lock owner, the holder pid and the age, and say that a lock younger than 1800 s may still belong to a run that is starting. Only an explicit yes counts.
5. **Act.** Run `janitor-report.sh act --confirm <id>...` with the picked ids, and `janitor-report.sh act --confirm --force-unlock <id>` once per confirmed force-unlock row. `act` re-runs each row's reader immediately before acting and refuses any row whose state changed (`janitor: refused <id> — …`). It then runs only that row's executor and prints `janitor: act <id> — <action>: <what the helper said>`, followed by a fresh `janitor: summary — …` line.
6. **Report back** every `act` and `refused` line as printed, and the fresh summary line.

## Safety

- `act` acts only with `--confirm`, never under `--report`, and never when `CI` is set. That guard lives in the script, so prose cannot skip it.
- A stray process is stopped only through `proc-registry.sh stop-unregistered`, with the lstart and command-line hash the report recorded. The registry re-checks both immediately before TERM and again before KILL, and refuses a live registry entry or a pid the scan no longer counts. A look-alike that is a live host session, runs under one, or has one running under it is action `none`, and so is every look-alike and overdue entry when janitor's process snapshot could not be taken.
- Rows in the plugin-adjacent and not-the-plugin's groups have action `none`. `act` refuses them, and their reason names the native way to close each one.
- The lanes group reads `lane-status --leaks` in compare mode only and never takes a snapshot.

## See Also

- `scripts/janitor-report.sh` is the engine, and its header is the contract. `scripts/test-janitor-report.sh` tests it on a hermetic fixture.
- `scripts/proc-registry.sh` (`list --scan`, `reap`, `stop-unregistered`), `run-lock.sh`, `automate-helpers.sh sweep` / `lane-status` / `lane-remove` / `config-restore`, `retention-sweep.sh` and `ci-slot.sh` are the readers and executors it calls.
- `docs/LANE_GATES.md` lists the `JAN-ACT` gate (human-only). `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory" holds its can't-ask row.
