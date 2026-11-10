# Unattended runs refuse to continue with the test-integrity guard unarmed

## Status: pending

Source: archive Batch F, item F2 story F2b (`batchF/2026-11-03-041412-unattended-runs-refuse-to-continue-with-the-test-integrity-guard-unarmed.md`). F2a (the arm-point audit and its `guard-arm-points.json`) was rejected and F2c (old CLI / hooks not loaded) moved to item 08, so this story stands alone and depends on neither.

**As the** owner (Vikash), who runs Supervisor, `/automate` phase sessions and detached review drains with nobody watching,
**I want** an unattended run whose test-integrity guard failed to arm to **stop with a named reason** before any worker or fix agent edits code,
**so that** the guard that keeps workers from editing tests, lint config and hooks is actually on whenever I am not there to read the warning.

### Problem (verified on main 8ec200e / v17.35.1)

`guard-test-integrity.sh` enforces only while the session has a marker (`.supervisor/guard/<session_id>.json`); with no marker it allows everything. Every arm point today treats a failed arm as "proceed":

1. **Supervisor driver INIT step 7** (`scripts/supervisor-next-step.sh`, `sn_init`): the comment reads "a failed arm is recorded, never fatal". `guard_armed: failed: <stderr>` goes to the Decisions Log and the run continues to ACQUIRE, PLAN and Phase 3, **including under `--non-interactive` / `--subagent`**. `sn_test_guard` reports `unarmed (<reason>)` only at the Phase 4.5 handover, after the workers ran.
2. **Detached drain** (`scripts/dispatch-pr-review.sh`): `… guard-arm.sh arm dispatcher --session-id "$GUARD_SESSION_ID" >/dev/null 2>&1 || true`, commented "a failed pre-arm still launches … this dispatcher never blocks a review drain on the guard".
3. **review-heal loop entry** (`skills/review-heal/SKILL.md` Step 2): a prose step, "proceed visibly unguarded … Never block loop entry on this." It sits in the default (Step 2) loop section. The `--until-mergeable` loop is run by `scripts/review-heal-next-step.sh`, which runs no arm at all.
4. **`PreToolUse[Agent|Task]` backstop** (`guard-arm.sh arm-from-payload`, `|| true` in `hooks.json`): it arms only for `*:worker|*:execute-manager|*:supervisor-runner|*:review-pr-runner`. The `--until-mergeable` drain's fix worker is a `general-purpose` agent (`review-heal-next-step.sh`, the `fix worker` spawn), so the backstop never fires for it.
5. **Consequence for `/automate`:** the default fresh phases run the drain as its own headless session (`automate-lanes.d/phase.sh`, `LOOMWRIGHT_PHASE_DIR` exported). That session has a new session id, nothing deterministic arms it, and its fix worker is not a backstop role. `docs/HOOKS.md` §"Guard contract" says the owned drain is "already covered by the Supervisor's own marker from the same session"; that is true only under `--inline-phases`.

The bimodal invariant (`CLAUDE.md` §"Failure-Mode Invariants") requires a correctness gate to fail CLOSED under `--non-interactive` with a named status, and to proceed only with an explicit `--skip-*`. None of the arm points above do this.

## Acceptance Criteria

Fixtures: `test-supervisor-next-step.sh` with `SUPERVISOR_NEXT_STEP_GUARD_CMD` stubbed to fail (exit 3, `guard_arm_failed: no session id`) plus new `fixtures/supervisor-golden/` cases; a temp guard dir; `test-review-heal-next-step.sh` fixtures; `test-dispatch-pr-review.sh` with a stub `claude`. No network.

**"Unattended" is one rule per driver:**
- Supervisor driver: the sidecar's `non_interactive` flag is set (`--non-interactive`, or `--subagent`, which implies it), **or** `LOOMWRIGHT_PHASE_DIR` is non-empty (an `/automate` or lane phase session; `phase.sh` exports it).
- review-heal driver: `LOOMWRIGHT_PHASE_DIR` is non-empty.
- The detached dispatcher: always unattended.

**Happy path**
- [ ] Given a driver-path Supervisor run with `--non-interactive` and a failing arm stub, when INIT runs, then the INIT Context-Keeper spawn still records `guard_armed: failed: guard_arm_failed: no session id`, and the next instruction is a `park` with `status: failed` and `error: test_guard_unarmed`, its message naming the reason and `--skip-test-guard`. The brief is moved to `failed/` (as `sn_preflight_fail_closed` does), and no `acquire`, branch, worktree, worker or execute-manager spawn is emitted. *(test-supervisor-next-step.sh, a new golden case `init-guard-unarmed-non-interactive`)*
- [ ] Given the same failing arm with `--subagent`, or with `LOOMWRIGHT_PHASE_DIR` set and no `--non-interactive`, then INIT parks the same way. *(test-supervisor-next-step.sh)*
- [ ] Given the same failing arm in an attended run (no `non_interactive`, no `LOOMWRIGHT_PHASE_DIR`), then INIT proceeds and records `guard_armed: failed: …` exactly as today (byte-identical golden output). *(test-supervisor-next-step.sh, existing `init-flags-*` goldens unchanged)*
- [ ] Given an unattended driver-path run that armed at INIT and whose marker is gone before Phase 3, when the `execute` or `execute-resume` step runs, then the driver re-runs the idempotent arm and reads the marker the way `sn_test_guard` does. When that read is `unarmed (<reason>)`, it parks `status: checkpoint`, `error: test_guard_unarmed`, and emits no worker or execute-manager spawn. `armed` and `not_applicable` (host mode, where the guard denies everything) proceed. *(test-supervisor-next-step.sh)*
- [ ] Given `review-heal-next-step.sh <pr> --start drain` with `LOOMWRIGHT_PHASE_DIR` set and an arm that fails, when `start` runs, then the driver itself has run `guard-arm.sh arm review-heal`, and the run ends `decision: ESCALATED` before any `fix worker` or `validate findings` spawn, following the existing `fix_floor_invalid` precedent: `escalation_cause: other`, `test_guard_unarmed: <reason>` leading `summary`, the terminal PR comment and the notification. *(test-review-heal-next-step.sh)*
- [ ] Given the same arm failure without `LOOMWRIGHT_PHASE_DIR`, then the drain proceeds and records `guard_armed: failed: …`, as today's prose step does. Given an arm that succeeds, the instruction stream is unchanged apart from that record. *(test-review-heal-next-step.sh)*
- [ ] Given a detached-drain dispatch whose pre-arm fails, then the stub `claude` is never invoked. The worktree and lock are torn down and no dispatch marker is written (so a later dispatch after the cause is fixed is not blocked), the dispatcher log carries `refused: test_guard_unarmed (<reason>)`, the existing best-effort notification names it, and the script still exits 0. *(test-dispatch-pr-review.sh)*

**Override (explicit, flag-only)**
- [ ] Given `--skip-test-guard` on `supervisor-next-step.sh --job …` (from `/supervisor --skip-test-guard`) with a failing arm while unattended, then the run proceeds and the Decisions Log records `guard_armed: skipped_by_flag` (with the failure reason). The same holds for `review-heal-next-step.sh --start drain --skip-test-guard` (from `/review-pr --skip-test-guard`). *(test-supervisor-next-step.sh, test-review-heal-next-step.sh)*
- [ ] Given `/automate --skip-test-guard`, then `automate-next-step.sh` adds `--skip-test-guard` to every Supervisor invocation it builds (the fresh phase and the inline `--continue`), to its drain invocation (`/review-pr … --skip-test-guard`), and to `/autonomous --single-iteration`, which forwards it in its EXECUTE `/supervisor` forward set. Without the flag, none of these carry it. *(test-automate-next-step.d)*
- [ ] Given `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` in the driver's environment and a failing arm while unattended, then the park still fires: the env opt-out is not an override for this gate. *(test-supervisor-next-step.sh)*

**Error scenarios / mutation**
- [ ] Given a mutation that (a) makes `sn_init` ignore the failed arm when unattended, (b) drops the `execute` step's marker read, (c) restores `|| true` and the launch on the dispatcher pre-arm, (d) makes the review-heal `start` step skip the arm, or (e) lets the environment opt-out satisfy the gate, then at least one test fails for each. *(the tests above)*
- [ ] No config key or env var turns the gate off: `grep -rn "skip_test_guard\|SKIP_TEST_GUARD" loomwright/scripts loomwright/skills loomwright/agents loomwright/commands` finds no config read or env read, only the CLI flag parsing and its docs. *(test-supervisor-next-step.sh, one grep assertion)*

## Non-goals
- Changing what `guard-test-integrity.sh` denies, its marker format, its env opt-out or its honest limits. No new `guard-arm.sh` subcommand and no change to the guard's Bash matcher: the drivers read the marker directly, as `sn_test_guard` already does.
- Making the `arm-from-payload` hook leaf blocking or widening its role list. It stays a `|| true` emitter.
- Interactive (attended) runs: they keep today's record-and-proceed.
- The prose (non-driver) Supervisor paths (`--continue`, `--legacy`, `--sdk-runner`) and Phase 4.5 fix-task spawns. They run in a session armed at INIT or by the backstop, and the handover's `test_guard` still reports.
- Host-version and hooks-not-loaded detection (item 08), and an arm-point audit file (F2a, rejected).
- A config key or env var form of the override.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): F2a (audit) rejected and F2c folded into item 08; this story keeps neither and does not create `guard-arm-points.json`.
- Standing owner rule: a guard found failing open gets its own P1 fix story (this one).
- OQ-F13. PO default, pending owner review: fail closed only when unattended (`--non-interactive`/`--subagent`, `/automate` and lane phase sessions via `LOOMWRIGHT_PHASE_DIR`, the detached drain). Attended runs keep record-and-proceed.
- OQ-F14. PO default, pending owner review: the override is the explicit `--skip-test-guard` flag only, recorded in the Decisions Log. It is not a config key or env var, and `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS` does not satisfy the gate, because an agent can set it on its own Bash call.
- PO default, pending owner review: the `verify` subcommand from the source is dropped. The drivers' own marker read covers the need without opening another `guard-arm.sh` subcommand through the guard's deny matcher.
- PO default, pending owner review: the review-heal refusal mirrors `fix_floor_invalid` (ESCALATED, `escalation_cause: other`, reason leading `summary`). It adds no new `termination_reason` enum value.
- PO default, pending owner review: an INIT park moves the brief to `failed/` (nothing has started), and a Phase 3 pre-spawn park is a `checkpoint` (resumable once the cause is fixed).
- PO default, pending owner review: the dispatcher refusal writes no dispatch marker (the same teardown as its other pre-launch refusals) instead of the source's `.died`-style marker, which counts toward the re-dispatch limit.

## Priority: P1 (MVP)
**Rationale:** The guard silently stops enforcing in exactly the runs nobody watches. With `/automate`'s default fresh phases, the drain session is never armed by anything deterministic.

## Assumptions
- The Supervisor's `--session-id` (`$SID`) is the Claude session id that `guard-arm.sh arm` reads from `CLAUDE_CODE_SESSION_ID`, so the driver's marker read and its arm name the same file (today's handover `test_guard` already relies on this).
- `LOOMWRIGHT_PHASE_DIR` reaches the drain phase session's Bash environment (it is exported on the `claude` process by `phase.sh`; `launch.sh` unsets it for lane launches, and a lane's own phases set it again).
- A lane running `--inline-phases` runs Supervisor in the lane session itself. If such a lane carries neither `--non-interactive` nor `LOOMWRIGHT_PHASE_DIR`, it counts as attended under this story. The implementer confirms this and states it in the PR.

## Dependencies
- Depends on: none.
- Blocks: item 08 (config integrity) touches the same `sn_init` area, so the two stories are serialized.

## Risks
- **More parks on hosts where arming fails for an environmental reason** (no `jq`, an unwritable guard dir). Mitigation: the reason is named and `--skip-test-guard` is the explicit escape.
- **Lane `--inline-phases` gap:** see Assumptions. If it holds, closing it needs a lane signal set by `automate-lanes.d/launch.sh` (one more file).
- **Mirror drift:** the arm-point contract is restated in `docs/HOOKS.md` §"Guard contract", `skills/supervisor-config/SKILL.md`, `skills/review-heal/SKILL.md`, `docs/supervisor-legacy-phases.md` and the loop inventories. All of them change in the same PR, and HOOKS.md's stale "same session" claim for the owned drain is corrected.
- **Prompt growth:** declared token budgets for the edited agents, commands and skills (`check-token-budget.sh`). Incident history goes in the changelog fragment, not the prompts (`check-prompt-history-refs.sh`).

## Validation (must pass before merge)
1. **Static — driver gates:** `test-supervisor-next-step.sh` (new golden cases plus the unchanged `init-flags-*` goldens), `test-review-heal-next-step.sh`, `test-dispatch-pr-review.sh` and `test-automate-next-step.d` cover every AC above, mutation legs included.
2. **Static — repo gates:** `bash scripts/ci-local.sh --affected` passes, including `test-guard-test-integrity.sh`, `test-guard-onfailure.sh`, `check-token-budget.sh`, `check-doc-currency.sh`, `check-prompt-history-refs.sh` and `test-citation-drift.sh`. The PR carries a `changelog.d/` fragment and never hand-edits a version file, and `bash scripts/check-version-bump.sh` passes.
3. **Running system — an unattended Supervisor with a broken arm parks:** a live headless `/supervisor job: <throwaway brief> --non-interactive` in a sandbox repo, with the guard dir made unwritable, ends `SUPERVISOR_RESULT status: failed` naming `test_guard_unarmed` before any worker spawn. The same run with `--skip-test-guard` proceeds and logs `guard_armed: skipped_by_flag`. Transcript excerpts and the Decisions Log go in the PR.

## Depends on
none

## Touches
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/test-supervisor-next-step.sh
loomwright/scripts/fixtures/supervisor-golden
loomwright/scripts/review-heal-next-step.sh
loomwright/scripts/test-review-heal-next-step.sh
loomwright/scripts/dispatch-pr-review.sh
loomwright/scripts/test-dispatch-pr-review.sh
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.d
loomwright/skills/review-heal/SKILL.md
loomwright/skills/supervisor-config/SKILL.md
loomwright/skills/autonomous-loop/SKILL.md
loomwright/agents/supervisor.md
loomwright/commands/supervisor.md
loomwright/commands/review-pr.md
loomwright/commands/automate.md
loomwright/commands/autonomous.md
loomwright/docs/HOOKS.md
loomwright/docs/supervisor-legacy-phases.md
loomwright/docs/result-schemas/supervisor-result.md
loomwright/docs/result-schemas/autonomous-run.md
loomwright/docs/result-schemas/review-heal-next-step.md
loomwright/docs/loop-inventory/review-heal.md
loomwright/docs/loop-inventory/supervisor.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/unattended-runs-refuse-unarmed-test-guard.md

## Changes since the source was written
- **F2a removed:** there is no `guard-arm-points.json` read or write. The source's audit-row updates are gone.
- **F2c removed:** host-version and hooks-not-loaded detection now belong to item 08.
- **`guard-arm.sh verify` dropped:** the Supervisor driver already reads the marker without a `guard-arm.sh` subcommand (`sn_test_guard`), so the story reuses that read and leaves the guard's Bash matcher untouched.
- **New finding:** `/automate`'s fresh phases (now the default) run the owned drain as its own headless session, with nothing deterministic arming it. The `--until-mergeable` driver runs no arm, and its `general-purpose` fix worker is not a backstop role. The arm therefore moves into `review-heal-next-step.sh start`, and HOOKS.md's "same session" claim is corrected.
- **"Unattended" made mechanical:** the `non_interactive` sidecar flag, or `LOOMWRIGHT_PHASE_DIR` (exported by `phase.sh`), in place of the source's prose list.
- **Env opt-out no longer satisfies the gate:** the source let `LOOMWRIGHT_ALLOW_GATE_CONFIG_EDITS=1` pass as `armed optout`. An agent can set it on its own Bash call, so it is not an override.
- **review-heal refusal shape:** it mirrors `fix_floor_invalid` and adds no `termination_reason` enum value. The dispatcher refusal writes no marker, where the source used a `.died`-style marker.
- **Scope trimmed:** the Phase 4.5 per-fix-spawn check and the prose `--continue`/`--legacy` paths are now non-goals. The `/autonomous` forwarding of `--skip-test-guard` was added so `/automate --inline-phases` can reach the override.
