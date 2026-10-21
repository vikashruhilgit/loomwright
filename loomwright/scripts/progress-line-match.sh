#!/usr/bin/env bash
# progress-line-match.sh — the ONE matcher for a run file's "Launch Pad saved a brief" `## Progress`
# line: Plan's end and Build's start. MEANT TO BE SOURCED; it only sets PROGRESS_PLAN_END_JQ.
#
# WHY ONE COPY. read-token-ledger.sh (--per-item phase windows) and the /lanes step timeline
# (automate-lanes.d/status-read.sh `_lanes_timeline`) each kept their own pattern for this line, and
# they drifted: the ledger accepted the driver's pinned `launch-pad saved <brief>` line
# (automate-next-step.sh plan-result, skills/automate-loop/per-item-loop.md step 2), while the timeline
# required the words "brief saved". Every fresh-phase lane's Build step then showed no start time
# (run automate-2026-10-15-163325, L21–L25, 2026-10-21).
#
# PROGRESS_PLAN_END_JQ is a jq `def`, prepended to a reader's program. `plan_end` is true for a Progress
# line's text (the part after `<ts> `) that starts, case-insensitively, with any spelling run files carry:
# the driver's `launch-pad saved <brief>`, and the model-written `launch-pad: brief saved <brief>`,
# `launch pad: brief saved <brief>` and `Launch Pad saved brief …` of earlier runs.
# A reader that cannot source this file uses `def plan_end: false;` — the boundary reads as not recorded,
# never as a wrong time. test-automate-next-step.sh R12 extracts the `^`-anchored prefix below: every
# spelling it admits must stay in the driver's NS_RESERVED_PREFIXES.
PROGRESS_PLAN_END_JQ='def plan_end: test("^launch[- ]?pad:?( brief)? saved"; "i");'
