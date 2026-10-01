# 02 — Completion-evidence integrity (no vacuous FINALIZE pass; one worker spawn shape)

## Problem
Two defects let a Supervisor run reach FINALIZE/merge with less completion evidence than the contract claims.

1. **Vacuous FINALIZE pass.** FINALIZE Point 5 (`agents/supervisor.md:444`) runs
   `check-children-settled.sh --all` and treats `status: "no_identity_rows"` as a PASS ("nothing to check"). The
   script returns `no_identity_rows` for a missing OR empty log (verified by running it on synthetic logs). But a
   run that DID spawn workers and whose `PostToolUse[Task]` identity rows never landed (hook not fired, log dir
   unresolvable, `jq` missing, a non-Claude host) produces exactly the same status — so the one whole-session
   completion check passes on zero evidence. The per-subtask gates (single-agent `--agent-id` at
   `supervisor.md` step 3b and `execute-manager.md:442`) fail closed on the same absence (`unsettled`), so the two
   checks disagree about what "no rows" means.
2. **Two worker spawn shapes.** `skills/async-orchestration/SKILL.md:172` (the first "Spawning a Worker" example)
   and `skills/workflow-management/SKILL.md:232` spawn workers as `subagent_type: "general-purpose"`, while
   `agents/execute-manager.md:185` and `async-orchestration/SKILL.md:773` use `loomwright:worker`. Every
   worker-specific hook is wired to the `loomwright:worker` matcher in `hooks/hooks.json` (SubagentStop →
   `validate-worker-result.py` + `emit-progress-event.sh`), and `guard-arm.sh arm-from-payload` arms only for
   `*:worker|*:execute-manager|*:supervisor-runner|*:review-pr-runner`. A worker spawned from the general-purpose
   example is therefore never result-validated, never writes its `subtask_complete` row, and never arms the
   test-integrity guard.

## Goal
FINALIZE can only report `children_check: settled` or `no_identity_rows` when the evidence supports it, and there is
exactly one documented worker spawn shape that every worker hook fires on.

## Scope
1. **`check-children-settled.sh --all --expect-id <id>` (repeatable).** When one or more expected ids are passed:
   every expected id must have a terminal row (same join as single-agent mode: `subtask_complete` non-rejected,
   `token_ledger`, `agent_lifecycle{state:failed}`), else `status: "unsettled"` with the missing ids in
   `unsettled_agent_ids`, regardless of whether any `agent_identity` rows exist. A missing/empty log WITH expected
   ids ⇒ `unsettled` (never `no_identity_rows`). No `--expect-id` ⇒ today's behaviour byte-for-byte (backward
   compatible for pre-existing callers and old logs). Update the script header's output-shape block.
2. **Supervisor FINALIZE Point 5** passes `--expect-id` for every worker/agent id this run spawned and already
   checked in the per-subtask gates (Single-Agent step 3b, Sequential per-subtask join, Execute Manager's
   per-worker join). The ids are already in hand at those gates — record them where FINALIZE can read them (the
   Context-Keeper Worker Results row, or the per-subtask gate's own log line; pick the existing surface, do not add
   a new state file, and state the choice in the PR). `no_identity_rows` remains a PASS only when the run spawned
   nothing. Mirror the change in `skills/async-orchestration/SKILL.md` §FINALIZE (the `--all` call near line 544)
   and `ARCHITECTURE_CONTRACTS.md` if it restates Point 5.
3. **One worker spawn shape.** Change the two `general-purpose` worker examples to `loomwright:worker` (keep every
   other field). Grep `agents/`, `skills/`, `commands/` for any other worker spawn that is not `loomwright:worker`
   and fix or justify each in the PR body. Non-worker `general-purpose` spawns (e.g. fixers in review-heal, the
   `/autonomous` review step) are OUT of scope — list them in the PR body so it is visible they were considered.
4. **Tests:** extend `test-check-children-settled.sh` (or create it if absent): expected id with no log ⇒
   unsettled; expected id with identity row only ⇒ unsettled; expected id with terminal row ⇒ settled; no
   expected ids + empty log ⇒ `no_identity_rows` (unchanged). A seam test greps FINALIZE Point 5 prose for
   `--expect-id`. A seam test asserts no `subagent_type: "general-purpose"` remains in a worker-spawn example
   (define the grep narrowly so the fixer spawns do not trip it). **Mutation control:** make the script ignore
   `--expect-id` ⇒ the no-log case must fail its test.
5. Docs: CHANGELOG, version bump, token budgets if `supervisor.md` / `execute-manager.md` grow.

## Non-goals
Moving completion to a file protocol (Phase 2). Changing the interactive `AskUserQuestion` (proceed / investigate /
abort) or the `--skip-children-check` escape hatch at Point 5. Changing the `verify-provides.sh` disk gate (it stays
the FIRST of the two AND-ed conditions). Touching non-worker `general-purpose` spawns.

## Acceptance criteria
- `check-children-settled.sh --log /nonexistent --all --expect-id a1` ⇒ `"status":"unsettled"`,
  `"unsettled_agent_ids":["a1"]`, exit 0.
- `check-children-settled.sh --log /nonexistent --all` ⇒ `"status":"no_identity_rows"` (unchanged).
- `grep -n 'expect-id' loomwright/agents/supervisor.md` ≥ 1 in Point 5; the Point 5 prose states that
  `no_identity_rows` passes only when no agent was spawned.
- `grep -rn 'subagent_type: "general-purpose"' loomwright/skills/async-orchestration/SKILL.md
  loomwright/skills/workflow-management/SKILL.md` returns no worker-spawn example.
- Full test loop + root checks + token budgets green.

## Verified premises (re-check before starting)
- `check-children-settled.sh` `--all` branch: missing log ⇒ `no_identity_rows` (header lines ~38-40, code ~125-129);
  single-agent missing log ⇒ `unsettled` (~132-134). Ran both on 2026-09-30.
- `agents/supervisor.md:444` Point 5 wording: "`status: "no_identity_rows"` … PASSES this point".
- `hooks/hooks.json` SubagentStop matcher `loomwright:worker` → validate-worker-result.py + emit-progress-event.sh.
- `scripts/guard-arm.sh` `cmd_arm_from_payload` case list (`*:worker|*:execute-manager|*:supervisor-runner|
  *:review-pr-runner`).
- The two `general-purpose` worker examples at `async-orchestration/SKILL.md:172` and
  `workflow-management/SKILL.md:232` (both unchanged between `d927996` and `a262d00`).

## Status: pending
