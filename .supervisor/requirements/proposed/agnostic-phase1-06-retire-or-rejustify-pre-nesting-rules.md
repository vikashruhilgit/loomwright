# agnostic-phase1/06 — Re-justify or retire the three rules whose only reason was "subagents cannot spawn subagents"

## Status: proposed

> Filed 2026-10-12 by owner decision during the agnostic-phase1/05 docs sweep. Not enqueued; promote by moving it out of `proposed/`.

## Problem
Claude Code now lets a subagent spawn subagents up to three layers below the main conversation by default
(`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`; v2.1.219+ default three — verified 2026-10-12 against
https://code.claude.com/docs/en/sub-agents). The agnostic-phase1/05 sweep rewrote every "subagents cannot spawn
subagents" claim and found three rules whose ONLY stated reason was that premise. They were left in place, marked
"retained pending owner review; see agnostic-phase1/05", pointing at `loomwright/docs/ARCHITECTURE_CONTRACTS.md`
§"Subagent nesting":
1. **AC9 — `review-pr-runner` is never Task-spawned** (review-heal §"Execution-contract rule (AC9)", `agents/review-pr.md`).
2. **Inline `/review-pr`** — the command must run on the main thread (the command body's "Execute this workflow inline" callout).
3. **Detached `/pr-postmortem` launch** — `dispatch-pr-postmortem.sh` starts a fresh `claude -p` process rather than a Task spawn.

A rule with no true reason is a "claim no check backs": it constrains the design for nothing, or it hides a real
reason nobody wrote down.

## Goal
Each rule either gets a real, written, tested reason or is retired.

## Scope
For each of the three rules:
1. **Probe it** on the current CLI: spawn the thing the rule forbids (e.g. `Task(loomwright:review-pr-runner)` from a
   main-thread session; `/review-pr` delegated to a subagent; `/pr-postmortem` as a Task) and record what actually
   happens — including spawn-depth headroom when the parent is itself a subagent (`/automate` → `/autonomous` →
   Supervisor → workers already spends depth), the ask-tool loss inside a subagent, and the detached-process
   properties (survives the parent turn ending, no shared context window) that the postmortem launch may genuinely need.
2. **Decide** (owner): keep with the real reason written down (and, where the reason is a runtime property, a test or
   a probe fixture that pins it), or retire the rule and simplify the code/prose.
3. Remove the "retained pending owner review" markers either way.

## Non-goals
- No change to the inline-only rule for `/supervisor`, `/launch-pad`, `/autonomous`, `/automate` — those have real
  reasons (a subagent has no `AskUserQuestion`; each layer spends nesting depth), already written in §"Subagent nesting".

## Acceptance criteria
- Each of the three rules has either a written reason backed by a probe result or test, or is removed.
- `grep -rn 'retained pending owner review' loomwright/` returns nothing.

## Depends on
none

## Touches
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/skills/review-heal/SKILL.md
loomwright/agents/review-pr.md
loomwright/commands/review-pr.md
loomwright/scripts/dispatch-pr-postmortem.sh
changelog.d/agnostic-phase1-06-pre-nesting-rules.md
