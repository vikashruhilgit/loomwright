# af/39 Part B — Silent script failures: run-lock liveness outside Claude Code, guard hook-arm visibility

## Status: pending

## Split from
`automate-followups/39-engine-hygiene.md` Part B (itself merged from `agnostic-phase1/03`), split 2026-10-13 per af/39's
2026-10-12 Re-scope ("Recommend B alone (medium) and A alone (large)"). Part B's text below is carried VERBATIM; the
two decisions it left open are now made (below) and they OVERRIDE the "consider (and decide in the PR)" wording in
Scope 1. Part A is `39a-sweep-and-janitor.md`; Part C shipped in #490.

## Split 2026-10-14 (owner, run automate-2026-10-13-181331)
Scopes 3–4 (the guard-arm trace and the `test_guard:` line) and owner decision 3 MOVED to
`39c-guard-arm-trace.md`: they edit `scripts/guard-arm.sh`, which the armed test-integrity guard denies to an
ordinary run (verified 2026-10-14 against the installed v17.2.0 guard — see 39c "Why it was split"). **This item
is now Scopes 1, 2, 5 (run-lock tests) and 6 (docs) only**, with owner decisions 1–2. The decision-3 text, the
`arm-skipped.jsonl` acceptance line and the guard bullets below are kept for history; 39c is their authority.
`guard-arm.sh` and `test-guard-test-integrity.sh` are out of this item's Touches.

## Depends on
none

## Touches
loomwright/scripts/run-lock.sh
loomwright/scripts/test-run-lock.sh
loomwright/scripts/guard-arm.sh
loomwright/scripts/test-guard-test-integrity.sh
loomwright/agents/supervisor.md
loomwright/commands/supervisor.md
loomwright/skills/supervisor-config/SKILL.md
loomwright/skills/autonomous-loop/SKILL.md
loomwright/skills/automate-loop/
loomwright/docs/HOOKS.md
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/docs/vendor-coupling-manifest.json
loomwright/docs/prompt-token-budgets.json
changelog.d/af39b-run-lock-and-guard-arm.md

## Owner decisions (2026-10-13 — decided, do not re-open in the PR)
1. **Holder resolution order** (`holder_pid()` in `run-lock.sh`), first match wins:
   1. `LOOMWRIGHT_HOLDER_PID` — NEW, vendor-neutral: any harness, CI job or terminal script names its own long-lived
      process. Valid only when numeric and alive. Recorded `pid_source holder_env`.
   2. `CLAUDE_PID` — kept as Claude Code's alias (`pid_source claude_pid`, unchanged). Keep it listed in
      `docs/vendor-coupling-manifest.json`; the new variable is NOT a coupling.
   3. The ancestor walk — run UNCONDITIONALLY (drop the `CLAUDECODE` gate), skipping shells AND two named lists
      (each entry added with a test):
      - short-lived wrappers: `env`, `timeout`, `xargs`, `sudo`;
      - long-lived session hosts: `tmux`, `screen`, `sshd`, `login`, and the terminal apps (`Terminal`, `iTerm2`).
      A host in the second list is never recorded: a crashed run under tmux must stay TTL-reclaimable.
      `pid_source ancestor`.
   4. `$PPID` — `pid_source ppid` plus the `run_lock_degraded: pid_source=ppid ttl_only=1800s` stderr line (Scope 2).
   `test-run-lock.sh` test 18 flips accordingly (it asserted the old CLAUDECODE-gated behaviour) — flip it, do not delete it.
2. **Start-time fingerprint.** `write_meta` also records the holder's start time (`ps -o lstart= -p <pid>`, works on
   macOS and Linux) as `pid_start`. At reclaim, the holder counts as alive only when `kill -0` succeeds AND its current
   `lstart` equals `pid_start` — a reused pid reads dead. A meta with no `pid_start` (written by an older version) keeps
   today's `kill -0`-only rule. Reclaim still needs BOTH dead AND age ≥ 1800 s; TTL and `--force-unlock` unchanged.
3. **Where a skipped guard arm is recorded** (Scope 3): the session log `.supervisor/logs/<session_id>.jsonl` when the
   payload carries a valid session id; otherwise (`no_session_id`, or a log dir that cannot be resolved for that id) ONE
   fixed file, `.supervisor/guard/arm-skipped.jsonl`, beside the per-session `<id>.json` markers — NOT under `logs/`, so
   readers that glob `logs/*.jsonl` are unaffected, and its `.jsonl` suffix never matches the markers' `*.json`.
   `jq_missing` rows are written with `printf`. Supervisor's `test_guard:` line (Scope 4) reads both. Still always
   exit 0; the hook keeps `|| true`.

## Added acceptance (for the decisions above)
- `LOOMWRIGHT_HOLDER_PID=<live pid>` ⇒ meta `pid_source holder_env` with that pid; a dead or non-numeric value is
  ignored and resolution falls through.
- A fixture parent named `tmux` (or `sshd`) above only shells ⇒ `pid_source ppid` + the degraded line, never the host.
- Pid reuse: a meta whose `pid_start` differs from the live pid's `lstart` ⇒ reclaimable once age ≥ 1800 s; a matching
  `pid_start` ⇒ held. A meta with no `pid_start` ⇒ today's behaviour.
- `no_session_id` arm skip ⇒ one row in `.supervisor/guard/arm-skipped.jsonl`, none under `logs/`.
- Mutation controls: re-adding the `CLAUDECODE` gate fails the ancestor test; dropping the `pid_start` comparison fails
  the reuse test.

## Validation (must pass before merge)
1. Targeted tests (`test-run-lock.sh`, `test-guard-test-integrity.sh`, plus any test pinning `supervisor.md` text) +
   doc-currency + citation-drift (+ token-budget for `supervisor.md`, vendor ratchet after `git add`). Full `ci-local`
   runs on GitHub CI (owner rule 2026-10-12).
2. Running system: one real `run-lock.sh acquire` from a plain terminal (no Claude env) — paste the meta and the
   degraded line; one with `LOOMWRIGHT_HOLDER_PID=$$` from a long-lived shell — paste `pid_source holder_env`.
3. Rollback: `git revert` (a meta written with `pid_start` stays readable by the old code — it ignores unknown keys;
   confirm that in the PR).

## Source text (af/39 Part B, carried verbatim — not part of the Validation section)

### Part B — 03 — Silent script failures (run-lock liveness outside Claude Code; guard hook-arm visibility)

#### Problem
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

#### Goal
The run lock records a live holder whenever one exists (under any harness) and says so loudly when it cannot; a
guard arm that did not happen leaves a durable, readable trace — without changing either script's exit-code
contract.

#### Scope
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

#### Non-goals
Changing the TTL (1800 s), `--force-unlock`, or the reclaim rule (pid dead AND age ≥ TTL). Adding a heartbeat.
Making `arm-from-payload` exit non-zero or removing its `|| true`. Changing which roles arm the guard (item 02 fixes
the spawn shape that bypassed it). Any change to `guard-test-integrity.sh`'s deny logic.

#### Acceptance criteria
- `env -u CLAUDE_PID -u CLAUDECODE <live non-shell parent> bash run-lock.sh acquire --owner t --root <scratch>`
  ⇒ meta `pid_source ancestor`, `kill -0 <pid>` succeeds.
- Only-shell parents ⇒ stderr contains `run_lock_degraded: pid_source=ppid`; exit code as before.
- `printf '{"tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | bash guard-arm.sh arm-from-payload`
  in a scratch project ⇒ exit 0 and one `guard_arm_skipped` row with `reason: no_session_id`.
- `grep -c '|| true' ` on the hooks.json guard-arm leaves unchanged; the two `guard-test-integrity.sh` leaves still
  carry none.
- Full test loop + root checks green.

#### Verified premises (re-check before starting)
- `run-lock.sh` header resolution order (lines ~26-40, incl. the 2026-09-26 observation) and `holder_pid()`
  (~173-193); reclaim rule (~240-250).
- `guard-arm.sh` `cmd_arm_from_payload` (~193-206): every non-arming branch is a bare `exit 0`.
- Prior decisions NOT to re-litigate: red-team-hardening/06 (lock shape, TTL, human-only `--force-unlock`);
  six-phase-loop-gaps/02 Rev 4 (one marker per session, no overwrite rule, no tool-call disarm, `arm` exits 3 on
  no id).

bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-14T15:51:26Z
- **Brief:** .supervisor/jobs/done/2026-10-14-af39b-run-lock-holder.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/542
