# `check-children-settled.sh` treats a non-plugin (`general-purpose`) spawn as never settled

## Status: pending

> **Promoted from `proposed/` 2026-10-01** (owner triage session).
> **Origin (2026-10-01).** Supervisor FINALIZE pre-merge gate point 5 on item automate-followups/13 (run
> automate-2026-09-30-054439) reported `unsettled` for three `general-purpose` agents that had demonstrably finished
> (completion notifications + SubagentHandback reports received). Owner chose "proceed + draft follow-up".

## Evidence
- `.supervisor/logs/<session>.jsonl`: each of the three agents has an `agent_identity` row (agent_type
  `general-purpose`) and only `agent_lifecycle` `state: working` rows — no `subtask_complete` / `token_ledger` /
  `agent_lifecycle: failed` terminal row. The `loomwright:loomwright:worker` in the same session has `subtask_complete`
  rows and settles.
- `check-children-settled.sh --all` joins EVERY `agent_identity` row against a terminal row, so any Launch Pad
  discovery / research spawn of a non-plugin type in the same session makes point 5 fail (interactive ⇒ ask;
  `--non-interactive` ⇒ fail CLOSED `children_unsettled`), even though nothing is unfinished.

## Scope (recommendation — trace before fixing)
- Confirm which hook writes the terminal row and why it does not fire (or is filtered) for `general-purpose`
  SubagentStop payloads (identity rows ARE written for them, so the asymmetry is the defect).
- Either emit a terminal `agent_lifecycle` row for every SubagentStop that has an identity row, or scope `--all` to
  agent types whose stop is observed — never silently drop the check. Fixture: a session log with a settled
  general-purpose spawn must read `settled`.

## Second cause seen (2026-10-04, wave w1 lane w1-08) — widens this item
The children-settled gate also failed on two **plugin** agents: `loomwright:loomwright:context-keeper` runs that hit
Context-Keeper's 3-turn limit AFTER their writes landed (verified in the lane's `state.md`: the pre-flight decision
and the worker-result row). Each had only `agent_identity` + `working` rows, no terminal row. So the gap is not only
"non-plugin agent types have no SubagentStop matcher": **any child that ends by hitting its turn limit leaves no
terminal lifecycle row**, and the gate cannot tell it from a hung child. The fix must cover both: a terminal row
(e.g. `agent_lifecycle: ended reason=max_turns`) for every SubagentStop, whatever the agent type and however it
ended. Both lanes' owners answered "proceed anyway", so this gate is producing human questions that carry no signal.

## Depends on
none

## Touches
loomwright/hooks/hooks.json
loomwright/scripts/check-children-settled.sh
loomwright/scripts/test-check-children-settled.sh
loomwright/scripts/emit-lifecycle.sh
loomwright/scripts/test-emit-lifecycle.sh
loomwright/docs/HOOKS.md
loomwright/docs/RESULT_SCHEMAS.md
changelog.d/automate-followups-17-children-settled-non-plugin-spawns.md
