# 03 — Silent script failures (run-lock liveness outside Claude Code; guard hook-arm visibility)

## Problem
Two fail-safe scripts fail *silently* in ways that weaken the guarantee they exist for.

1. **`run-lock.sh` records a pid that is already dead.** `holder_pid()` (`scripts/run-lock.sh:173-193`) resolves the
   liveness pid as `CLAUDE_PID` (if alive) → the first non-shell ancestor, but ONLY when `CLAUDECODE` is set → else
   `$PPID`. Outside Claude Code (a CI step, a terminal, any other harness) the `$PPID` is the invoking shell, which
   exits right after `acquire`. Exercised 2026-09-30 against a scratch `--root`: with `CLAUDE_PID`/`CLAUDECODE`
   unset, meta recorded `pid_source ppid` and that pid was dead immediately; a second owner was refused while the
   lock was young (TTL) but TOOK the lock once `ts` was ≥1800 s old — i.e. any run lasting over 30 minutes can be
   double-entered. The header (`:36-38`) acknowledges the TTL degradation but nothing surfaces it at acquire time.
   The ancestor walk itself is harness-neutral; only its `CLAUDECODE` gate is Claude-specific.
2. **The guard's hook arm path fails invisibly.** `guard-arm.sh arm-from-payload` (the `PreToolUse[Agent|Task]`
   backstop, carried with `|| true`) exits 0 without arming when `jq` is missing, the payload's
   `tool_input.subagent_type` is not one of the four armed roles, the payload has no valid `session_id`, or the
   marker write fails — and records nothing anywhere. The prompt-step `arm` is loud (exit 3,
   `guard_arm_failed: no session id`), but when the backstop is the arm that mattered, a session can run a
   Loomwright worker with the test-integrity guard never armed and no one can tell afterwards.

## Goal
The run lock records a live holder whenever one exists (under any harness) and says so loudly when it cannot; a
guard arm that did not happen leaves a durable, readable trace — without changing either script's exit-code
contract.

## Scope
1. **run-lock `holder_pid()`**: run the ancestor walk unconditionally (drop the `CLAUDECODE` gate); keep
   `CLAUDE_PID` first; `$PPID` only when the walk finds no non-shell ancestor > 1. Keep the `pid_source` values
   (`claude_pid` | `ancestor` | `ppid`). Consider (and decide in the PR) whether a non-shell ancestor that is a
   short-lived wrapper (e.g. `env`, `timeout`, `xargs`, `sudo`) must be skipped like a shell — add them to the skip
   list only with a test.
2. **Degraded-lock warning**: when the recorded source is `ppid`, `acquire` prints one stderr line
   `run_lock_degraded: pid_source=ppid ttl_only=1800s` (exit code unchanged) and `status` shows it. Callers that
   already surface `run_lock_held` (automate PICK, Supervisor INIT, `/autonomous` INIT) surface this line too —
   verify each caller's prose, do not add new gates.
3. **Guard arm trace**: `arm-from-payload` appends ONE JSONL row to the session log the other emitters use
   (`.supervisor/logs/<session_id>.jsonl`, resolved the same way `emit-agent-identity.sh` resolves it) when it
   declines to arm for a role it SHOULD arm (`subagent_type` in the armed set) — reasons: `jq_missing` (write via
   printf, no jq), `no_session_id`, `marker_write_failed`. Event name `guard_arm_skipped` with `reason` and
   `subagent_type`. Non-armed roles stay silent (that is correct behaviour, not a failure). Still ALWAYS exit 0;
   the hook keeps `|| true`. If no log dir can be resolved, write nothing (fail-safe) — state that limit.
4. **Surface it**: Supervisor FINALIZE (or the run summary it already prints) reports `test_guard: armed | unarmed
   (<reason>) | not_applicable` for its own session, read from the marker file + the `guard_arm_skipped` rows.
   Advisory only — it must not block, park, or change any decision.
5. **Tests**: `test-run-lock.sh` — with `CLAUDE_PID`/`CLAUDECODE` unset and a non-shell parent (spawn the script
   from a `python3 -c 'subprocess…'` or `perl` parent that stays alive), `pid_source` is `ancestor` and the pid is
   alive; with only shells above, `ppid` + the degraded stderr line. Guard: fixture payloads for each skip reason
   ⇒ one `guard_arm_skipped` row, exit 0; non-armed role ⇒ no row. **Mutation control:** re-add the `CLAUDECODE`
   gate ⇒ the ancestor test must fail.
6. Docs: script headers, `HOOKS.md` guard row, CHANGELOG, version bump.

## Non-goals
Changing the TTL (1800 s), `--force-unlock`, or the reclaim rule (pid dead AND age ≥ TTL). Adding a heartbeat.
Making `arm-from-payload` exit non-zero or removing its `|| true`. Changing which roles arm the guard (item 02 fixes
the spawn shape that bypassed it). Any change to `guard-test-integrity.sh`'s deny logic.

## Acceptance criteria
- `env -u CLAUDE_PID -u CLAUDECODE <live non-shell parent> bash run-lock.sh acquire --owner t --root <scratch>`
  ⇒ meta `pid_source ancestor`, `kill -0 <pid>` succeeds.
- Only-shell parents ⇒ stderr contains `run_lock_degraded: pid_source=ppid`; exit code as before.
- `printf '{"tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | bash guard-arm.sh arm-from-payload`
  in a scratch project ⇒ exit 0 and one `guard_arm_skipped` row with `reason: no_session_id`.
- `grep -c '|| true' ` on the hooks.json guard-arm leaves unchanged; the two `guard-test-integrity.sh` leaves still
  carry none.
- Full test loop + root checks green.

## Verified premises (re-check before starting)
- `run-lock.sh` header resolution order (lines ~26-40, incl. the 2026-09-26 observation) and `holder_pid()`
  (~173-193); reclaim rule (~240-250).
- `guard-arm.sh` `cmd_arm_from_payload` (~193-206): every non-arming branch is a bare `exit 0`.
- Prior decisions NOT to re-litigate: red-team-hardening/06 (lock shape, TTL, human-only `--force-unlock`);
  six-phase-loop-gaps/02 Rev 4 (one marker per session, no overwrite rule, no tool-call disarm, `arm` exits 3 on
  no id).

bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`

## Status: pending
