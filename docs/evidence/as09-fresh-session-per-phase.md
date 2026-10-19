# Evidence — automate-speed/09: fresh session per phase

Requirement: `.supervisor/requirements/automate-speed/09-fresh-session-per-phase.md` (gitignored; a clone may not have it).
Branch: `feature/fresh-session-per-phase`. Code commits: `9d407a9` and `f63bb27` (phase runner, relay routing, run-lock
re-entry), then `a45e25c` and `c8e57ee` (driver and phase-timing). Doc commits: `49cb927` and `7a33706`.

## Validation step 1 — the suites (run at `7a33706`, macOS, bash 3.2)

Each suite ran in the foreground, one call at a time. Every script these suites exercise is byte-identical
between `c8e57ee` and `7a33706`, because the two doc commits change only docs, skills and command prose.

| Suite | Result line | Passed / total | Wall |
|---|---|---|---|
| `loomwright/scripts/test-automate-next-step.sh` | `PASS: 151 FAIL: 0` | 151/151 | 328 s |
| `loomwright/scripts/test-automate-lanes.sh` | `passed: 993  failed: 0` | 993/993 | 215 s |
| `loomwright/scripts/test-automate-golden.sh` | `PASS: 65 FAIL: 0` | 65/65 | 51 s |
| `loomwright/scripts/test-run-lock.sh` | `RESULT: 88 passed, 0 failed` | 88/88 | 8 s |

The doc gates also pass at `7a33706`:

- `scripts/check-doc-currency.sh`
- `scripts/check-token-budget.sh` (`commands/automate.md` 7524/7565 proxy tokens, no ceiling raised)
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
