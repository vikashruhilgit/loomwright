# Evidence — automate-speed/09: fresh session per phase

Requirement: `.supervisor/requirements/automate-speed/09-fresh-session-per-phase.md` (gitignored; a clone may not have it).
Branch: `feature/fresh-session-per-phase`. Code commits: `9d407a9` and `f63bb27` (phase runner, relay routing, run-lock
re-entry), then `a45e25c` and `c8e57ee` (driver and phase-timing), then the two review-fix commits `6316c0c`
(iteration 1) and `05aa192` (iteration 2: re-print identity rebuilt per session, died-phase fallbacks). Doc commits:
`49cb927`, `7a33706` and `36f1bb7`.

## Validation step 1 — the suites (run at `05aa192`, the final code head; macOS, bash 3.2)

Every count below was measured at `05aa192`, the last commit that changes code or tests. The only commit after it is
this evidence refresh, which changes nothing but this file, so the counts hold for the branch head. Each suite ran
in the foreground, one call at a time.

| Suite | Result line | Passed / total | Wall |
|---|---|---|---|
| `loomwright/scripts/test-automate-next-step.sh` | `PASS: 153 FAIL: 0` | 153/153 | 327 s |
| `loomwright/scripts/test-automate-lanes.sh` | `passed: 995  failed: 0` | 995/995 | 207 s |
| `loomwright/scripts/test-automate-golden.sh` | `PASS: 65 FAIL: 0` | 65/65 | 48 s |
| `loomwright/scripts/test-run-lock.sh` | `RESULT: 88 passed, 0 failed` | 88/88 | 8 s |

The doc gates also pass at `05aa192`:

- `scripts/check-doc-currency.sh`
- `scripts/check-token-budget.sh` (`commands/automate.md` 7521/7565 proxy tokens, no ceiling raised)
- `scripts/check-vendor-coupling.sh` (0 breaches)
- `loomwright/scripts/test-loop-inventory.sh` (43/43)
- `loomwright/scripts/test-citation-drift.sh` (26/26)
- `loomwright/scripts/test-automate-loop-split.sh` (40/40)
- `scripts/check-version-bump.sh` (not bumped; 1 fragment pending, which is legal)

These suites read the edited prose and pass too:

- `test-automate-dismissed.sh` (255/255)
- `test-automate-trail.sh` (786/786)
- `test-non-interactive-gates-seam.sh` (64/64)

## Validation step 2 — running system: STILL TO RUN (the owner's step)

The owner still has to run one real Queue item end to end with `/automate` (no `--inline-phases`) and record:

- the three phase session ids, one from each `## Progress` line `session_id <sid> (<item>) phase=launch-pad|supervisor|drain`;
- the coordinator's peak context from item 03's report (`read-token-ledger.sh --per-item`, `phase-timing.sh`);
- a check of the coordinator transcript showing it never read `agents/launch-pad.md`, `agents/supervisor.md`,
  `skills/self-heal-advisory/` or `skills/review-heal/`.

A PR cannot run this step, because it needs the real `claude` CLI, a real requirement and the owner at the relay.

## Not verified (stub-only surfaces)

Every phase-session leg above runs against the suites' `claude` stub. None of the following has been seen running on
the real CLI:

- the `--settings` relay-hook merge into a real `claude -p` session, and whether hook processes inherit
  `LOOMWRIGHT_PHASE_DIR` / `LOOMWRIGHT_RUN_LOCK_SESSION_ID`;
- a real `AskUserQuestion` deferral (`stop_reason: tool_deferred`) and `--resume` delivering the answer to the same session;
- a real `phase-launch` → `phase-wait` → `--result` loop longer than one 540 s `phase-wait` window;
- the coordinator re-asking a relayed question verbatim, and its can't-ask branch. This is prose the model follows
  (loop-inventory GAP rows AL-575 and AL-581);
- inside a `--parallel` lane, a relayed lane-policy gate (e.g. `LP-SAVE`) still being answered by the lane policy
  when the coordinator re-asks it.

## Known limits

- A stale `.supervisor/state.md` from an earlier item can make the launch-pad or drain phase's ledger file under the
  old plugin id, because `emit-token-ledger.sh` prefers `state.md`. That is existing emitter behaviour, and it affects
  the per-phase measurement.
- Fresh phases do not forward `--notify`. Its gate webhooks belong to `/autonomous`, which fresh phases bypass, so
  `--notify` takes effect only under `--inline-phases`. The fresh Supervisor prompt's `--cheap` / `--max-tokens`
  forwarding has no test (loop-inventory GAP AL-586).
- A Supervisor phase that dies without a `SUPERVISOR_RESULT` still stops the item with the no-PR line. An open PR it
  left is named on that line only when `.supervisor/state.md` was rewritten by that phase and records the branch.
  The PR is never drained or merged; the owner handles it.
