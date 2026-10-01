# `check-children-settled.sh` treats a non-plugin (`general-purpose`) spawn as never settled

## Status: proposed

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
