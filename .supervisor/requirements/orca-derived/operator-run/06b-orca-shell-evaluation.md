# 06b — Orca as the D2 shell: evaluation inputs (operator-run planning item — NOT for `/automate`)

Split out of 06 §B on 2026-09-12. Blocked on final-state execution-order item 5 (arm-3 re-run) and feeds
item 10 (D2 standalone app). `orca` is NOT installed on the dev machine as of 2026-09-11; installing it is
the operator's first step. The decision is written to `FINAL_STATE_GOAL.md` as a D2 amendment — never here.

## Inputs to record
Question for step 10: build a shell, or make the judgment layers an Orca skill (`orca skills install`) and
skip the shell. Inputs to record BEFORE deciding, all operator-run inside Orca on `ai-agent-manager`
opened as a workspace (NOT a child worktree — `.supervisor/` is gitignored and would be empty):
- Where Orca writes its managed status hooks (`jq .hooks ~/.claude/settings.json` before/after) and whether
  they coexist with `hooks.json` without double-firing side effects (double toasts expected; anything else is a finding).
- Does `AskUserQuestion` inside a worker show as *Needs You*; do worker/reviewer spawns appear as child rows.
- Does the `/autonomous` non-interactive false-positive (memory `autonomous-tty-false-positive`) still trip
  under Orca's real PTY.
- Nested worktrees: does Orca's sidebar show/interfere with Supervisor-created worktrees.
Risk to weigh: dependency on a YC startup's roadmap (MIT + adapter seam bound it). Decision goes in
`FINAL_STATE_GOAL.md` as a D2 amendment, never here.


## Findings
_(none yet — one dated line per input above, with the exact command)_

## Status: operator-run (blocked on final-state 05)
