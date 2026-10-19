# supervisor-next-step.sh reads nested `###` tables as subtask ids

## Status: proposed

## Problem
`scripts/supervisor-next-step.sh` `sn_brief_subtasks` takes the first cell of EVERY table row from `## Subtask Structure` down to the next `## ` heading. A Supervisor-Ready Brief nests `### File Impact Map` (and `### Subtask Contracts`) under that heading, and when the File Impact Map's first column holds one-word group names (`core`, `checker`, `until-mergeable`), those names and the header word `Group` pass the id regex `^[A-Za-z0-9._-]{1,64}$` and become subtasks.

Observed 2026-10-19, lane L15 of run automate-2026-10-15-163325 (item automate-speed/14): the driver's plan sidecar read `["1","2","3","Group","core","until-mergeable"]`. After subtasks 1–3 passed every per-subtask gate, it printed a worker spawn for subtask `Group`. The only answers it accepts are a fabricated `passed` or a `paused` park. The merged item-13 brief (`2026-10-16-diet-launch-pad-autonomous.md`) has the same shape and parses to `1 2 3 Group checker launch-pad autonomous`.

## Goal
The plan is exactly the `## Subtask Structure` table's own rows.

## Acceptance criteria
- `sn_brief_subtasks` stops at the first `### ` heading (or at the end of the first table) after `## Subtask Structure`; nested tables never contribute ids.
- A golden test uses a brief whose `### File Impact Map` first column holds one-word group names, and the plan equals the subtask table's ids only. Mutation: drop the stop-at-`###` clause ⇒ the test goes red.
- Optional hardening: the parsed ids are cross-checked against the `# Subtask N` blocks in `### Subtask Contracts`, and a mismatch refuses at plan time rather than at the execute step.

## Touches
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/test-supervisor-next-step.sh
