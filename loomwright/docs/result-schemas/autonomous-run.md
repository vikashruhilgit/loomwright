## AUTONOMOUS_RUN

Emitted by the `/autonomous` inline main-thread workflow (v13.0.0+; bumped to `schema_version: 2` in v14.0.0). Written to `.supervisor/autonomous/{session_id}/summary.md` (human-readable markdown) with a machine-readable sidecar at `.supervisor/autonomous/{session_id}/state.json`. Also echoed to main-thread output for user visibility.

**Not subject to hook validation.** `AUTONOMOUS_RUN` is autonomous-layer-only; the existing `hooks/hooks.json` SubagentStop validators target `SUPERVISOR_RESULT`, `WORKER_RESULT`, etc., and explicitly do *not* validate `AUTONOMOUS_RUN`. The status enum is intentionally distinct from `SUPERVISOR_RESULT.status` (`completed | completed_with_escalation | failed | checkpoint`) to prevent confusion and to keep the two layers separable.

**v1 → v2 transition (v14.0.0):** schema_version was bumped from `1` to `2` to admit the v14 continuous-mode `status_reason` values (nine new closed values introduced when multi-iteration became the default and the non-interactive / stacked-branch paths landed). Because no SubagentStop hook validates this block, the bump is forward-only and **schema-1 emissions remain accepted** for the transition window — tooling that parses the block SHOULD accept either `schema_version: 1` or `schema_version: 2` and treat unknown `status_reason` values as opaque strings rather than rejecting. New emissions on v14.0.0+ MUST use `schema_version: 2`.

```yaml
AUTONOMOUS_RUN:
  schema_version: 2                    # integer, required — v2 in v14.0.0+ (v1 emissions still accepted; see transition note above)
  session_id: string                   # required — "auto-{YYYY-MM-DD}-{HHMMSS}". v1 second-precision is sufficient under the single-session assumption; v2 may append a random suffix (e.g., "-{4hex}") to harden against same-second collisions when concurrent sessions are supported.
  requirement_path: string             # required — path to the requirement file under .supervisor/requirements/
  mode: enum [single, multi]           # required — multi-iteration is the v14 default; single requires --single-iteration (or --max-iterations 1)
  allow_multi_iteration: boolean       # required — true iff the deprecated --allow-multi-iteration was explicitly supplied; false on the default multi-iter path (v14) and on single-iter runs
  max_iterations: integer              # required — the cap that was in effect for this run (1..N). For single-iteration runs (mode == "single"), this field MUST be 1 — the implicit cap. For multi-iteration runs, it carries the --max-iterations value (default 3). Recording this makes runs that end with status: paused_max_iterations self-diagnosable: a reader can tell whether the cap was the default 3 or a user-supplied custom value.
  status: enum [done, paused_max_iterations, aborted, failed]  # required — autonomous-layer status
  status_reason: string | null         # required — null when status: done AND no rubric stop; otherwise one of the documented reason strings (see below)
  total_iterations: integer            # required — 0..max_iterations (0 when the loop aborted during PLAN before any EXECUTE)
  last_phase: enum [PLAN, EXECUTE, EVALUATE, DONE]  # required — phase the loop was in at exit
  started_at: string                   # required — ISO-8601 UTC timestamp
  ended_at: string                     # required — ISO-8601 UTC timestamp
  duration_seconds: integer            # required — `ended_at - started_at`, rounded to the nearest second. v1 uses integer precision because the loop is foreground-assisted and human-paced (multi-iteration runs span minutes to hours); sub-second precision is not actionable. If telemetry ever aggregates sub-minute autonomous sessions, a v2 schema bump can widen this to `number` without breaking existing parsers (integer is a valid JSON number).
  iterations: object[]                 # required — one entry per iteration that reached EXECUTE (may be empty array [] for pre-EXECUTE aborts: Phase 6 discard, NO-GO abort, Plan Review FAIL × 3 abort)
    - n: integer                       # 1-indexed
      brief_path: string               # path to the brief Launch Pad saved; lifecycle-moved by Supervisor
      supervisor_status: enum [completed, completed_with_escalation, failed, checkpoint]  # normally mirrors `SUPERVISOR_RESULT.status`. EXCEPTION: when Supervisor exited without emitting a `SUPERVISOR_RESULT` block at all (crash, hard API error, etc.), the autonomous loop synthesizes this iteration entry with `supervisor_status: failed` and `error: "no_supervisor_result_emitted"` — see `skills/autonomous-loop/SKILL.md` EXECUTE step 5 for the synthesis algorithm. The enum value is the same in both cases; only the provenance differs.
      pr_url: string | null            # SUPERVISOR_RESULT.pr_url when present
      rubric_score: string | null      # SUPERVISOR_RESULT.rubric_score when present (format "N/M")
      branch: string                   # normally `SUPERVISOR_RESULT.branch`. EXCEPTION: the synthetic no-SUPERVISOR_RESULT entry uses the empty string `""` because no branch name was emitted — the iteration crashed before Supervisor produced a result block, so the loop has no authoritative branch to record. The empty string is a deliberate sentinel; merge verification on Signal 1 skips the local-ancestor fallback when `branch == ""` (see `skills/autonomous-loop/SKILL.md` Signal 1 merge-verification block, which already treats unresolvable branch SHAs as "merge unverifiable" and re-prompts the user).
      summary: string                  # SUPERVISOR_RESULT.summary
      error: string | null             # SUPERVISOR_RESULT.error when status: failed
      heal_decision: string | null     # SUPERVISOR_RESULT.heal_decision
      escalation_reason: string | null # populated for status: completed_with_escalation
  escalations_seen: string[]           # required — flattened list of escalation reasons across iterations (may be empty)
  policy_decisions: object[]           # required — user choices at loop-level AskUserQuestion gates AND loop-inferred records of decisions made inside Supervisor's adjudication
    - iteration: integer               # 0 for PLAN-phase decisions made before any EXECUTE happened
      phase: enum [PLAN, EVALUATE]
      decision: enum [                 # closed set — see decision enum table below
        "user_picked_save",
        "user_picked_discard",
        "user_picked_override",
        "user_picked_abort",
        "user_picked_merge_and_continue",
        "user_picked_stop_here",
        "user_picked_force_continue_anyway",
        "supervisor_option_c_detected",
        "pr_base_verify_skipped_non_interactive"
      ]
      source: enum [launch_pad_phase_6, launch_pad_no_go, launch_pad_plan_review, autonomous_rubric_gate, supervisor_adjudication, autonomous_pr_base_verify]
  rubric_final_score: string | null    # required — last iteration's rubric_score (null when no rubric in requirement OR when total_iterations == 0)
```

> **Auto-authored-rubric note (additive; no schema change):** In multi-iteration mode, when the requirement lacked an `## Outcomes Rubric` at intake, Launch Pad may **auto-author** one (human-approved, then frozen into the requirement body), so `rubric_final_score` can be non-null even for a requirement that started without a rubric. If auto-authoring fell back (fewer than 3 diff-checkable bullets were derivable), no rubric exists and `rubric_final_score` stays `null` — the existing no-rubric gate applies, unchanged. See `skills/autonomous-loop/SKILL.md` and `skills/supervisor-readiness/SKILL.md` §"Auto-Authoring (multi-iteration)" for the authoring rules.

**`status_reason` enum** (documented as a closed set; new values require updating both this schema and `skills/autonomous-loop/SKILL.md`). The mapping between `status` and the legal subset of `status_reason` values is fixed:

| `status` | Legal `status_reason` values |
|---|---|
| `done` | `null` (rubric satisfied or no rubric present), `"user_stopped_at_rubric_gate"` (user accepted partial rubric; PR exists, run ended on user's terms), `"user_stopped_at_no_rubric_gate"` (v14.0.0+; user picked stop at the no-rubric gate), `"no_rubric_in_non_interactive"` (v14.0.0+; non-interactive fallback at no-rubric gate — see Non-interactive fallback policy in `skills/autonomous-loop/SKILL.md` §"No-rubric gate") |
| `paused_max_iterations` | `"max_iterations_reached"` |
| `aborted` | `"user_discarded_at_phase_6"`, `"user_aborted_at_no_go"`, `"user_aborted_at_plan_review_fail"`, `"supervisor_checkpoint"`, `"rubric_dropped_from_brief"`, `"concurrent_session_detected"`, `"invalid_max_iterations"`, **v14.0.0+:** `"non_interactive_without_fallback"`, `"conflicting_mode_flags"`, `"iter_pr_base_mismatch"`, `"rubric_gate_closed_non_interactive"`, `"user_aborted_gh_retry"`, **v14.2.0+:** `"launch_pad_blocked"`, `"user_aborted_at_launch_pad"`, **agnostic-phase1/04:** `"review_heal_escalated_non_interactive"`, `"launch_pad_cant_ask_non_interactive"` |
| `failed` | `"supervisor_failed_other"`, **v14.0.0+:** `"supervisor_base_branch_mismatch"`, **v14.8.0+:** `"preflight_overlap_detected"` |

Reason-string meanings:

- `null` — `status: done` with rubric satisfied or no rubric present
- `"max_iterations_reached"` — multi-iteration mode hit the `--max-iterations` cap
- `"user_discarded_at_phase_6"` — user picked "discard" at Launch Pad's Phase 6 save prompt (pre-EXECUTE; `total_iterations == 0`, `iterations == []`)
- `"user_aborted_at_no_go"` — user picked "abort" at Launch Pad Phase 2.5 NO-GO escalation (pre-EXECUTE; `total_iterations == 0`)
- `"user_aborted_at_plan_review_fail"` — user picked "abort" after Plan Reviewer FAIL × 3 (pre-EXECUTE; `total_iterations == 0`)
- `"user_stopped_at_rubric_gate"` — user picked "stop-here" at the rubric-gate AskUserQuestion. The latest iteration's PR exists and Supervisor returned `completed`; the run ends successfully but with `rubric_score N<M` recorded in `rubric_final_score`. Pairs with `status: done` (not `aborted`) because nothing went wrong — the user accepted partial completion.
- `"supervisor_checkpoint"` — `SUPERVISOR_RESULT.status: checkpoint` (loop does not auto-resume in v1)
- `"supervisor_failed_other"` — covers two cases: (a) `SUPERVISOR_RESULT.status: failed` was emitted but without the `inter_subtask_gap` Option-C signal in any of the three iteration-scoped sources; (b) Supervisor crashed or otherwise exited without emitting any `SUPERVISOR_RESULT` block at all, and the autonomous loop synthesized a placeholder iteration entry with `error: "no_supervisor_result_emitted"` so the schema's `iterations.length == total_iterations` invariant still holds
- `"rubric_dropped_from_brief"` — Launch Pad did not preserve the `## Outcomes Rubric` section (rubric-preservation gate failure)
- `"concurrent_session_detected"` — brief-save `ls`-diff found more than one new file in `.supervisor/jobs/pending/` (violates v1 single-session assumption)
- `"invalid_max_iterations"` — `--max-iterations N` was passed where N is not in the valid range (N ≤ 0 or N > 10, or non-integer). INIT rejects this immediately, before any state.json/summary.md is written beyond the abort record. `total_iterations: 0`, `iterations: []`, `last_phase: PLAN`

**v14.0.0 status_reason additions** (paired with the v14 continuous-mode + non-interactive-fallback + stacked-branches work):

- `"non_interactive_without_fallback"` — the loop detected a non-interactive (no-TTY) environment at INIT and `--non-interactive-fallback` was NOT supplied. Pairs with `status: aborted`. Pre-EXECUTE; `total_iterations: 0`. See `skills/autonomous-loop/SKILL.md` §"INIT step 0".
- `"conflicting_mode_flags"` — both `--single-iteration` and `--allow-multi-iteration` (or equivalent conflict) were supplied. Pairs with `status: aborted`. Pre-EXECUTE; `total_iterations: 0`.
- `"iter_pr_base_mismatch"` — EVALUATE's PR-base verification (AC-3 + AC-15) found the iteration's PR was opened against a different base than the loop declared, AND the user-prompt-and-retry policy (AC-14) reached its terminal abort. Pairs with `status: aborted`. The offending iteration's entry is still present in `iterations[]` (it did reach EXECUTE).
- `"rubric_gate_closed_non_interactive"` — the rubric gate would have fired, but the loop was running with `--non-interactive-fallback` in a no-TTY environment. Fail-closed policy: the gate aborts the loop rather than silently picking `continue` or `stop`. Pairs with `status: aborted`.
- `"user_aborted_gh_retry"` — user explicitly aborted at the EVALUATE PR-base verification retry prompt (e.g., declined to retry a `gh` call after a transient failure). Pairs with `status: aborted`.
- `"supervisor_base_branch_mismatch"` — Supervisor's Phase 4 self-verify OR Phase 4.5 base-mismatch cleanup detected an unrecoverable base-branch divergence and emitted `SUPERVISOR_RESULT.status: failed` with the diagnostic. The autonomous loop surfaces this as `status: failed` (not `aborted`) because the failure originated below the loop. The iteration's `SUPERVISOR_RESULT.pr_state` typically carries `"closed_by_loop"` or `"close_attempt_failed"` for the cleanup case.
- `"user_stopped_at_no_rubric_gate"` — user picked "stop" at the v14 no-rubric gate (fires when the iteration had no rubric and the user is given an explicit continue/stop choice rather than the loop silently terminating). Pairs with `status: done` because the PR exists and the user ended the run on their own terms.
- `"no_rubric_in_non_interactive"` — the no-rubric gate's non-interactive-fallback policy: with no rubric signal to gate against, continuing in CI would be busywork, so the gate accepts the iteration cleanly. Pairs with `status: done` (NOT `aborted`) — this is the explicit non-failure CI exit. Contrast `"rubric_gate_closed_non_interactive"`, which fails closed because a rubric signal IS available and silently dropping it is unsafe.

**v14.2.0 status_reason additions** (paired with the LAUNCH_PAD_RESULT brief-detection work):

- `"launch_pad_blocked"` — Launch Pad emitted `LAUNCH_PAD_RESULT.status: blocked` (Phase 1 BLOCKER or Plan Review FAIL × 3 without override); the loop never reached EXECUTE. Pairs with `status: aborted`. Pre-EXECUTE; `total_iterations: 0`.
- `"user_aborted_at_launch_pad"` — Launch Pad emitted `LAUNCH_PAD_RESULT.status: aborted` (user killed the workflow mid-flight). Pairs with `status: aborted`. Pre-EXECUTE; `total_iterations: 0`.

Two new `policy_decisions[].decision` values also land in v14.2.0 (both audit-only records emitted during PLAN brief-detection, paired with `source: "autonomous_loop"`): `"launch_pad_result_malformed"` (the `LAUNCH_PAD_RESULT` block was present but failed `validate-launch-pad-result.py`, so the loop fell through to the `ls`-diff fallback) and `"launch_pad_result_fallback"` (no result block found — pre-v14.2.0 plugin or transcript-scan miss — so the `ls`-diff fallback was used).

**v14.8.0 status_reason addition** (paired with the Supervisor Phase 1.5 PRE-FLIGHT SYNC gate):

- `"preflight_overlap_detected"` — emitted when the Supervisor's Phase 1.5 PRE-FLIGHT SYNC gate fails closed under `--non-interactive` (or a non-TTY stdin) on an OVERLAP or SUPERSEDED classification, without `--skip-preflight-sync`. The Supervisor aborts before spawning any worker and emits `SUPERVISOR_RESULT.status: failed` with `error: "preflight_overlap_detected"`; the autonomous loop surfaces it as `AUTONOMOUS_RUN.status_reason: "preflight_overlap_detected"`. Pairs with `status: failed` (not `aborted`) because the failure originated below the loop, in the Supervisor's gate — mirroring `"supervisor_base_branch_mismatch"`. The offending iteration reached EXECUTE intake but no worker ran, so its entry (if any) carries the Supervisor's `failed` result. See `agents/supervisor.md` §"Phase 1.5: PRE-FLIGHT SYNC" and `skills/autonomous-loop/SKILL.md` EVALUATE termination table.

**agnostic-phase1/04 status_reason addition** (paired with the question-gate can't-ask branches, `docs/ARCHITECTURE_CONTRACTS.md` §"Question-gate inventory"):

- `"review_heal_escalated_non_interactive"` — EVALUATE's chained review-and-heal returned `ESCALATED` while the loop runs with `--non-interactive-fallback` (no TTY): nobody can pick continue / stop, so the loop asks nothing and aborts. Pairs with `status: aborted`; the PR stays open with its posted findings. See `skills/autonomous-loop/SKILL.md` §"EVALUATE review-heal step".
- `"launch_pad_cant_ask_non_interactive"` — the inlined Launch Pad stopped at a question gate it could not ask (it runs with `--non-interactive` under `--non-interactive-fallback`): `LAUNCH_PAD_RESULT.status` is `blocked` or `aborted` and its `summary` leads with the gate's named `*_non_interactive` status (the block has no key for it). Replaces `launch_pad_blocked` / `user_aborted_at_launch_pad` for that case, since no user aborted; summary.md keeps Launch Pad's `summary` verbatim on its `launch_pad_summary` line. Pairs with `status: aborted`. Pre-EXECUTE; `total_iterations: 0`.

**Validation rules:**
- No SubagentStop hook validates this block (autonomous-layer-only). The v1 → v2 bump in v14.0.0 is therefore forward-only — schema-1 emissions remain accepted by downstream tooling. Parsers SHOULD accept either `schema_version: 1` or `schema_version: 2` and SHOULD treat unrecognized `status_reason` values as opaque strings rather than rejecting.
- `iterations.length == total_iterations` (when `total_iterations == 0`, `iterations` MUST be an empty array `[]`; this is the pre-EXECUTE-abort case).
- `total_iterations >= 0` and `total_iterations <= max_iterations`. The pre-EXECUTE-abort paths (`user_discarded_at_phase_6`, `user_aborted_at_no_go`, `user_aborted_at_plan_review_fail`) all yield `total_iterations == 0`.
- `status` ↔ `status_reason` pairing must follow the table above. The four legal `done` reason values are: `null` (clean completion), `"user_stopped_at_rubric_gate"` (user accepted partial rubric), `"user_stopped_at_no_rubric_gate"` (v14.0.0+; user picked stop at no-rubric gate), and `"no_rubric_in_non_interactive"` (v14.0.0+; non-interactive fallback at no-rubric gate — loop accepts the iteration cleanly rather than aborting).
- When `total_iterations == 0`, `rubric_final_score` MUST be `null` and `last_phase` MUST be `PLAN`.
- When `total_iterations >= 1`, `rubric_final_score` mirrors the `rubric_score` of the last entry in `iterations`.
- Each `policy_decisions[]` entry's `decision` field MUST match a value from the closed `decision` enum in the YAML schema above. Each `(decision, source)` pair MUST follow the legal pairing table below.

**`policy_decisions.decision` enum** (closed set; new values require updating both this schema and `skills/autonomous-loop/SKILL.md`). The legal `(decision, source)` pairing table:

| `decision` | Legal `source` value | Captures |
|---|---|---|
| `"user_picked_save"` | `launch_pad_phase_6` | User confirmed brief save at Launch Pad Phase 6 |
| `"user_picked_discard"` | `launch_pad_phase_6` | User discarded brief at Launch Pad Phase 6 (terminal — produces `status: aborted`) |
| `"user_picked_override"` | `launch_pad_no_go`, `launch_pad_plan_review` | User overrode a NO-GO verdict or a Plan Review FAIL (loop continues) |
| `"user_picked_abort"` | `launch_pad_no_go`, `launch_pad_plan_review` | User aborted at NO-GO or after Plan Review FAIL × 3 (terminal — produces `status: aborted`) |
| `"user_picked_merge_and_continue"` | `autonomous_rubric_gate` | User confirmed merge and asked loop to proceed; merge-verified before re-plan |
| `"user_picked_stop_here"` | `autonomous_rubric_gate` | User accepted partial rubric (terminal — produces `status: done, status_reason: user_stopped_at_rubric_gate`) |
| `"user_picked_force_continue_anyway"` | `autonomous_rubric_gate` | User bypassed merge verification (loop continues; conflict risk recorded for audit) |
| `"supervisor_option_c_detected"` | `supervisor_adjudication` | **Loop-inferred from filesystem evidence** after Supervisor's own adjudication AskUserQuestion concluded. Unlike the `user_picked_*` entries, this decision was made inside Supervisor's session — the autonomous loop only records that it observed the result (failed brief in `.supervisor/jobs/failed/` + `inter_subtask_gap` substring). The `_detected` suffix is a deliberate naming convention to flag this distinction for future tooling. |
| `"pr_base_verify_skipped_non_interactive"` | `autonomous_pr_base_verify` | **Loop-recorded, no user choice** (agnostic-phase1/04): EVALUATE's PR-base verification could not read the PR's base (`gh pr view` failed twice) while running with `--non-interactive-fallback`, so the loop asked nothing and skipped the check for this iteration. Not a correctness bypass — Supervisor FINALIZE already verified the base or failed closed. See `skills/autonomous-loop/SKILL.md` §"EVALUATE PR-base verification (AC-3 + AC-15)". |

**Example — single-iteration successful run:**

```yaml
AUTONOMOUS_RUN:
  schema_version: 2
  session_id: auto-2026-05-11-143022
  requirement_path: .supervisor/requirements/auto-2026-05-11-143022-add-version-cmd.md
  mode: single
  allow_multi_iteration: false
  max_iterations: 1
  status: done
  status_reason: null
  total_iterations: 1
  last_phase: DONE
  started_at: 2026-05-11T14:30:22Z
  ended_at: 2026-05-11T14:36:11Z
  duration_seconds: 349
  iterations:
    - n: 1
      brief_path: .supervisor/jobs/done/auto-2026-05-11-143022-add-version-cmd.md
      supervisor_status: completed
      pr_url: https://github.com/example/repo/pull/42
      rubric_score: null
      branch: feature/add-version-cmd
      summary: Implemented /version command with unit tests.
      error: null
      heal_decision: PASS
      escalation_reason: null
  escalations_seen: []
  policy_decisions:
    - { iteration: 1, phase: PLAN, decision: "user_picked_save", source: "launch_pad_phase_6" }
  rubric_final_score: null
```

**Example — pre-EXECUTE abort (user discarded at Phase 6):**

```yaml
AUTONOMOUS_RUN:
  schema_version: 2
  session_id: auto-2026-05-11-150412
  requirement_path: .supervisor/requirements/auto-2026-05-11-150412-refactor-auth.md
  mode: single
  allow_multi_iteration: false
  max_iterations: 1
  status: aborted
  status_reason: "user_discarded_at_phase_6"
  total_iterations: 0
  last_phase: PLAN
  started_at: 2026-05-11T15:04:12Z
  ended_at: 2026-05-11T15:09:48Z
  duration_seconds: 336
  iterations: []
  escalations_seen: []
  policy_decisions:
    - { iteration: 0, phase: PLAN, decision: "user_picked_discard", source: "launch_pad_phase_6" }
  rubric_final_score: null
```

**Example — multi-iteration with rubric stop-here:**

```yaml
AUTONOMOUS_RUN:
  schema_version: 2
  session_id: auto-2026-05-11-160000
  requirement_path: .supervisor/requirements/auto-2026-05-11-160000-add-jwt.md
  mode: multi
  allow_multi_iteration: true
  max_iterations: 3
  status: done
  status_reason: "user_stopped_at_rubric_gate"
  total_iterations: 1
  last_phase: EVALUATE
  started_at: 2026-05-11T16:00:00Z
  ended_at: 2026-05-11T16:18:30Z
  duration_seconds: 1110
  iterations:
    - n: 1
      brief_path: .supervisor/jobs/done/auto-2026-05-11-160000-add-jwt.md
      supervisor_status: completed
      pr_url: https://github.com/example/repo/pull/77
      rubric_score: "3/5"
      branch: feature/add-jwt
      summary: JWT auth implemented; 2 rubric items deferred per user choice.
      error: null
      heal_decision: PASS
      escalation_reason: null
  escalations_seen: []
  policy_decisions:
    - { iteration: 1, phase: PLAN, decision: "user_picked_save", source: "launch_pad_phase_6" }
    - { iteration: 1, phase: EVALUATE, decision: "user_picked_stop_here", source: "autonomous_rubric_gate" }
  rubric_final_score: "3/5"
```

**Example — v14.0.0 CI run, non-interactive fallback at no-rubric gate (`no_rubric_in_non_interactive`):**

```yaml
AUTONOMOUS_RUN:
  schema_version: 2
  session_id: auto-2026-05-16-090000
  requirement_path: .supervisor/requirements/auto-2026-05-16-090000-ci-refactor.md
  mode: multi
  allow_multi_iteration: false
  max_iterations: 3
  status: done
  status_reason: "no_rubric_in_non_interactive"
  total_iterations: 1
  last_phase: EVALUATE
  started_at: 2026-05-16T09:00:00Z
  ended_at: 2026-05-16T09:11:42Z
  duration_seconds: 702
  iterations:
    - n: 1
      brief_path: .supervisor/jobs/done/auto-2026-05-16-090000-ci-refactor.md
      supervisor_status: completed
      pr_url: https://github.com/example/repo/pull/102
      rubric_score: null
      branch: feature/ci-refactor
      summary: Refactor landed cleanly; brief had no rubric so loop accepted the iteration in CI mode.
      error: null
      heal_decision: PASS
      escalation_reason: null
  escalations_seen: []
  policy_decisions:
    - { iteration: 1, phase: PLAN, decision: "user_picked_save", source: "launch_pad_phase_6" }
  rubric_final_score: null
```

**Cross-references:**
- `loomwright/skills/autonomous-loop/SKILL.md` — full protocol; this schema canonicalizes its `DONE — AUTONOMOUS_RUN Summary` section
- `loomwright/commands/autonomous.md` — slash command body
- `loomwright/docs/FAILURE_ESCALATION.md` — Option C is the loop's failed-iteration re-plan trigger
- `SUPERVISOR_RESULT` schema (above) — each `iterations[].supervisor_status` mirrors `SUPERVISOR_RESULT.status` for that iteration's run

---

