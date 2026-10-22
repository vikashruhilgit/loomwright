# af/39 Part B (guard half) — Silent script failures: guard hook-arm visibility

## Status: pending

## Split from
`automate-followups/39b-run-lock-and-guard-arm.md`, split 2026-10-14 by the owner during run
`automate-2026-10-13-181331` (Launch Pad Phase 2.5, a Hard Blocker). 39b keeps Scopes 1–2 (run-lock holder
resolution, start-time fingerprint, degraded-lock warning — owner decisions 1–2). This file carries Scopes 3–4
and owner decision 3 VERBATIM from 39b; the decision is already made and is not re-opened here.

## Why it was split (read before starting)
**This item edits `loomwright/scripts/guard-arm.sh`, a file the armed test-integrity guard protects.** Verified
2026-10-14 against the installed v17.2.0 guard on a scratch armed session: a `PreToolUse[Write|Edit]` payload for
`<repo>/loomwright/scripts/guard-arm.sh` is DENIED (rc 2 — `guard-arm.sh` is in the last arm of
`is_protected_basename` in `scripts/guard-test-integrity.sh`), while `run-lock.sh` is allowed (rc 0). Supervisor
arms the guard at Phase 0 INIT and the `PreToolUse[Agent|Task]` backstop arms on every worker spawn, so an
ordinary `/automate` / `/supervisor` run cannot make this change. **Run it only from a Claude Code session the
owner launched with the human-only opt-out in the launching shell's environment** (`docs/HOOKS.md` §"Guard
contract", "Opt-out — process env only"). Never set the opt-out from inside a session.

A second constraint found the same day: in an armed session the Bash matcher DENIES a tool call that invokes
`guard-arm.sh` with any subcommand other than a bare `arm` (verified: `bash loomwright/scripts/guard-arm.sh status`
→ rc 2). So the Scope 4 reader that Supervisor runs at its completion tail CANNOT be a new `guard-arm.sh`
subcommand — it must be a separate script (or a plain marker/JSONL read) that the guard does not single out.
Changing `guard-test-integrity.sh`'s deny logic stays a non-goal.

## Re-verified 2026-10-22 (read-only against main 7b7cb08 / v17.14.1 — read before starting; wins over the Source text)
- **Still open:** Scope 3 (`cmd_arm_from_payload` in `guard-arm.sh` still does a bare `exit 0` on every skip branch —
  jq missing, wrong role, invalid session id — and `write_marker … || true`; nothing emits `guard_arm_skipped`),
  Scope 4 (no `test_guard:` line anywhere), Scopes 5–6. The `|| true` on the `arm-from-payload` /
  `disarm-session` leaves in `hooks.json` still holds.
- **Guard dir moved (c10ac78, host mode):** it resolves through `host-mode.sh` to `<gate dir>/guard` and can be
  empty. Read decision 3's `.supervisor/guard/arm-skipped.jsonl` as `$GUARD_DIR/arm-skipped.jsonl`; an empty
  `GUARD_DIR` is a fourth skip reason (`no_guard_dir`) — record it in the session log when the id is valid, else
  print one stderr line; never write outside a resolved dir.
- **The `## Outcome` block moved** to `loomwright/skills/self-heal-advisory/completion-tail.md` (step 2), not
  `SKILL.md` Part 2.
- **Supervisor INIT is a script now:** the arm runs in `loomwright/scripts/supervisor-next-step.sh`'s `init` step
  (step-7 block, `guard_armed: ok|failed`), which calls `guard-arm.sh` as a subprocess the guard's Bash matcher
  never sees. The `test_guard:` reader lives in that driver as a plain JSONL/marker read — no new `guard-arm.sh`
  subcommand (still denied in an armed session). A standalone reader script is acceptable only if the driver's
  token budget forbids the addition; then add it and its test to Touches in the brief.
- **Unchanged premises:** `guard-arm.sh` is still in the last arm of `is_protected_basename`; the Bash matcher still
  denies any `guard-arm.sh` subcommand other than a bare `arm`.

## Owner decisions (from _BACKLOG.md)
- 2026-10-22: run this item ALONE, in its own sequential `/automate --requirement` run launched by the owner from a
  shell that exports the human-only opt-out — never inside a `--parallel` wave, so no other lane inherits
  gate-edit rights.

## Depends on
none

## Touches
loomwright/scripts/guard-arm.sh
loomwright/scripts/test-guard-test-integrity.sh
loomwright/scripts/supervisor-next-step.sh
loomwright/scripts/test-supervisor-next-step.sh
loomwright/skills/self-heal-advisory/completion-tail.md
loomwright/skills/supervisor-config/SKILL.md
loomwright/docs/supervisor-legacy-phases.md
loomwright/agents/supervisor.md
loomwright/commands/supervisor.md
loomwright/docs/HOOKS.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
changelog.d/af39c-guard-arm-trace.md

## Owner decision (2026-10-13 — decided, do not re-open in the PR)
3. **Where a skipped guard arm is recorded** (Scope 3): the session log `.supervisor/logs/<session_id>.jsonl` when the
   payload carries a valid session id; otherwise (`no_session_id`, or a log dir that cannot be resolved for that id) ONE
   fixed file, `.supervisor/guard/arm-skipped.jsonl`, beside the per-session `<id>.json` markers — NOT under `logs/`, so
   readers that glob `logs/*.jsonl` are unaffected, and its `.jsonl` suffix never matches the markers' `*.json`.
   `jq_missing` rows are written with `printf`. Supervisor's `test_guard:` line (Scope 4) reads both. Still always
   exit 0; the hook keeps `|| true`.

## Added acceptance (for the decision above)
- `no_session_id` arm skip ⇒ one row in `.supervisor/guard/arm-skipped.jsonl`, none under `logs/`.

## Validation (must pass before merge)
1. Targeted tests (`test-guard-test-integrity.sh`, plus any test pinning `supervisor.md` text) + doc-currency +
   citation-drift (+ token-budget for `supervisor.md`, vendor ratchet after `git add`). Full `ci-local` runs on
   GitHub CI (owner rule 2026-10-12).
2. Running system: from the opted-out session, pipe the three fixture payloads (`jq` hidden from PATH; no
   `session_id`; an unwritable guard dir) into the installed `guard-arm.sh arm-from-payload` — paste each exit code
   and the row it wrote; then one real Supervisor completion tail — paste its `test_guard:` line.
3. Rollback: `git revert`.

## Source text (af/39 Part B, carried verbatim — not part of the Validation section)

### Part B — 03 (guard half) — Silent script failures (guard hook-arm visibility)

#### Problem
2. **The guard's hook arm path fails invisibly.** `guard-arm.sh arm-from-payload` (the `PreToolUse[Agent|Task]`
   backstop, carried with `|| true`) exits 0 without arming when `jq` is missing, the payload's
   `tool_input.subagent_type` is not one of the four armed roles, the payload has no valid `session_id`, or the
   marker write fails — and records nothing anywhere. The prompt-step `arm` is loud (exit 3,
   `guard_arm_failed: no session id`), but when the backstop is the arm that mattered, a session can run a
   Loomwright worker with the test-integrity guard never armed and no one can tell afterwards.

#### Goal
A guard arm that did not happen leaves a durable, readable trace — without changing the script's exit-code
contract.

#### Scope
3. **Guard arm trace**: `arm-from-payload` appends ONE JSONL row to the session log the other emitters use
   (`.supervisor/logs/<session_id>.jsonl`, resolved the same way `emit-agent-identity.sh` resolves it) when it
   declines to arm for a role it SHOULD arm (`subagent_type` in the armed set) — reasons: `jq_missing` (write via
   printf, no jq), `no_session_id`, `marker_write_failed`. Event name `guard_arm_skipped` with `reason` and
   `subagent_type`. Non-armed roles stay silent (that is correct behaviour, not a failure). Still ALWAYS exit 0;
   the hook keeps `|| true`. If no log dir can be resolved, write nothing (fail-safe) — state that limit.
   (Owner decision 3 above refines the destination: the fixed `arm-skipped.jsonl` file when no session log
   resolves.) Note for `jq_missing`: the armed-role test currently runs through `jq`, so the jq-less path needs a
   jq-free read of `tool_input.subagent_type` (and `session_id`) to know the role is one it SHOULD arm.
4. **Surface it**: Supervisor FINALIZE (or the run summary it already prints) reports `test_guard: armed | unarmed
   (<reason>) | not_applicable` for its own session, read from the marker file + the `guard_arm_skipped` rows.
   Advisory only — it must not block, park, or change any decision. (The completion tail's job `## Outcome` block
   in `skills/self-heal-advisory/SKILL.md` Part 2 step 2 is the existing additive-markdown home; a new key inside
   the `SUPERVISOR_RESULT` block would fail `sidecar-check`'s closed key set. `skills/supervisor-config/SKILL.md`
   step 7 already promises a `guard: unarmed` mark there.)
5. **Tests**: Guard: fixture payloads for each skip reason ⇒ one `guard_arm_skipped` row, exit 0; non-armed role
   ⇒ no row.
6. Docs: script header, `HOOKS.md` guard row, CHANGELOG, version bump.

#### Non-goals
Making `arm-from-payload` exit non-zero or removing its `|| true`. Changing which roles arm the guard (item 02 fixes
the spawn shape that bypassed it). Any change to `guard-test-integrity.sh`'s deny logic.

#### Acceptance criteria
- `printf '{"tool_input":{"subagent_type":"loomwright:loomwright:worker"}}' | bash guard-arm.sh arm-from-payload`
  in a scratch project ⇒ exit 0 and one `guard_arm_skipped` row with `reason: no_session_id`.
- `grep -c '|| true' ` on the hooks.json guard-arm leaves unchanged; the two `guard-test-integrity.sh` leaves still
  carry none.
- Full test loop + root checks green.

#### Verified premises (re-check before starting)
- `guard-arm.sh` `cmd_arm_from_payload`: every non-arming branch is a bare `exit 0`.
- Prior decisions NOT to re-litigate: six-phase-loop-gaps/02 Rev 4 (one marker per session, no overwrite rule, no
  tool-call disarm, `arm` exits 3 on no id).

bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`
