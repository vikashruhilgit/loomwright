# Result Schemas

> Strict contracts for all agent result blocks. Hooks validate against these schemas.
> All schemas include a `schema_version` field for forward compatibility. Current versions: CODE_REVIEW_RESULT at `schema_version: 3` (review modes + consistency audit; v2 accepted for legacy); WORKER_RESULT at `schema_version: 2` (outputs_verified contract; v1 accepted for the v12.0.0 transition window); AUTONOMOUS_RUN at `schema_version: 2` (v14.0.0 status_reason extension; v1 accepted, no hook validation); LAUNCH_PAD_RESULT at `schema_version: 1` (added v14.2.0, validated by `scripts/validate-launch-pad-result.py`); REVIEW_HEAL_RESULT at `schema_version: 1` (added v14.16.0, no hook validator — runner is the main agent of its own session); EVAL_RESULT at `schema_version: 1` (added v14.17.0, the System Twin eval instrument emitted by `scripts/run-eval.sh`, no hook validator — standalone script); GROUND_TRUTH_JSON at `schema_version: 1` (added v14.19.0, the System Twin ground-truth instrument emitted by `scripts/run-ground-truth.sh`, no hook validator — standalone script; consumed advisory-only by Supervisor Phase 4.5); POSTMORTEM_RESULT at `schema_version: 1` (added v14.22.0, the advisory PR review-churn trend line appended by `/pr-postmortem` to `.supervisor/postmortem/results.jsonl`, no hook validator); all others at `schema_version: 1`.

> **API-level enforcement:** When using the Claude API directly (outside Claude Code), enforce these schemas via `output_config.format` (JSON Schema mode) for guaranteed conformance — the model is constrained to produce schema-valid output before the response is returned. Plugin hook validation (the `SubagentStop` hooks defined in `hooks.json`) is the runtime fallback validator inside Claude Code, where `output_config` is not available to plugin agents. See `AGENT_GUIDELINES.md` §"Structured Outputs" and the Anthropic API reference for the exact field name in your SDK version.

---

## WORKER_RESULT

Produced by Worker agent on task completion.

```yaml
WORKER_RESULT:
  schema_version: 2                    # integer, required — v2 adds outputs_verified + outputs_gap (v1 still accepted during the v12.0.0 transition window)
  task_id: string                      # required — subtask identifier (e.g., "BD-15a" or "add-auth-guard")
  status: enum [completed, failed, partial]  # required
  files_modified: string[]             # required — non-empty when status=completed
  files_created: string[]              # optional — new files created
  tests_added: string[]                # optional — test files added or modified
  tests_passed: boolean                # optional — true if all tests pass
  outputs_verified: object[]           # required (v2) — itemized verification of every output the brief promised
    - kind: enum [file, symbol, type]  # required — what was checked
      path: string                     # required — repo-relative path the check was performed against
      name: string                     # optional — symbol/type name (required when kind in {symbol, type})
      status: enum [present, missing]  # required — outcome of the check
  outputs_gap: string                  # required (v2) — empty string when nothing missing; non-empty implies status MUST be partial
  memory_candidates: string[]          # optional — additive, does NOT bump schema_version (stays 2; an optional, backwards-compatible field needs no bump); absent by default. Durable, reusable structural facts about the codebase proposed for project memory; NEVER secrets/PII/tokens. Workers PROPOSE only — they never write memory (worktree-write ban / red-team F1); promotion is human-gated.
  summary: string                      # required — max 200 tokens, what was done
  error: string                        # conditional — required when status=failed, describes what went wrong
```

**Validation rules (schema_version: 2):**
- `schema_version` must equal `2`
- `task_id` must be non-empty string
- `status` must be one of: `completed`, `failed`, `partial`
- When `status=completed`: `files_modified` must be non-empty array
- When `status=failed`: `error` must be present and non-empty
- `summary` must be present and under 200 tokens
- `outputs_verified` must be present (may be `[]` only when the brief promised no concrete outputs); each entry must have `kind`, `path`, `status`; entries with `kind ∈ {symbol, type}` must include `name`
- `outputs_gap` must be present as a string; an empty string means all promised outputs were delivered
- **Cross-field invariant (hook-enforced):** if `outputs_gap` is non-empty AND `status=completed`, the SubagentStop hook rejects with `outputs_gap non-empty must map to status: partial`. A worker that did not deliver all promised outputs has not completed.
- **Runtime checks performed by the SubagentStop hook (not part of the schema, listed for transparency):** the hook also verifies that a `.worker-summary.md` file was written and that no destructive commands (`rm -rf`, `git push`, `git reset --hard`, `DROP`, `TRUNCATE`) appear in the run output.
- `memory_candidates` is **optional and additive** — it does NOT bump `schema_version` (stays `2` — an optional, backwards-compatible field addition does not require a version bump; `schema_version` bumps only for breaking or required-field changes). When present it is an array of short strings; absent by default. Each candidate must be a **durable, reusable structural fact about the codebase** (not transient run notes) that is not already captured in `CLAUDE.md`. Candidates **MUST NEVER contain secrets, credentials, tokens, or PII**. Workers **PROPOSE only** and never write project memory — a worktree write would be lost on worktree removal (red-team F1), so workers never call `write-project-memory.sh`; promotion of any candidate into project memory is **human-gated** and happens at the repo root.

**Validation rules (schema_version: 1, legacy):**
- `schema_version` must equal `1`
- All v2 rules except `outputs_verified` and `outputs_gap` (which are not present in v1)
- v1 emissions remain accepted by the SubagentStop hook for the v12.0.0 transition window. Workers running on v12.0.0+ MUST emit v2.

**Example (v2, happy path):**
```
WORKER_RESULT:
  schema_version: 2
  task_id: add-jwt-guard
  status: completed
  files_modified: [src/auth/jwt.guard.ts, src/auth/jwt.strategy.ts]
  files_created: [src/auth/jwt.guard.spec.ts]
  tests_added: [src/auth/jwt.guard.spec.ts]
  tests_passed: true
  outputs_verified:
    - kind: file
      path: src/auth/jwt.guard.ts
      status: present
    - kind: symbol
      path: src/auth/jwt.guard.ts
      name: JwtGuard
      status: present
    - kind: file
      path: src/auth/jwt.guard.spec.ts
      status: present
  outputs_gap: ""
  summary: Implemented JWT guard with passport strategy. Added unit tests with 92% coverage.
```

**Example (v2, partial — gap reported):**
```
WORKER_RESULT:
  schema_version: 2
  task_id: add-jwt-guard
  status: partial
  files_modified: [src/auth/jwt.guard.ts]
  files_created: []
  outputs_verified:
    - kind: file
      path: src/auth/jwt.guard.ts
      status: present
    - kind: file
      path: src/auth/jwt.guard.spec.ts
      status: missing
  outputs_gap: "src/auth/jwt.guard.spec.ts"
  summary: Guard implemented but unit-test file deferred (Jest config absent in the worktree); status partial because outputs_gap names the missing spec.
```

---

## EXECUTE_RESULT

Produced by Execute Manager when all subtasks are completed.

```yaml
EXECUTE_RESULT:
  schema_version: 1                    # integer, required — always 1
  subtasks_completed: object[]         # required — non-empty array
    - task_id: string                  # subtask identifier
      status: completed                # always "completed" in this array
      branch: string                   # worktree branch name
      files_modified: string[]         # files changed by this subtask
      review_decision: string          # PASS (must be PASS to be in completed)
  subtasks_failed: object[]            # optional — subtasks that failed after retries
    - task_id: string
      status: failed
      error: string
      retry_count: integer
  merge_order: string[]                # required — ordered list of branches to merge
  worktrees: object[]                  # required — worktree details for cleanup
    - task_id: string
      path: string                     # absolute path to worktree
      branch: string                   # branch name in worktree
      status: enum [completed, failed, cleaned]
  branches: string[]                   # optional — all branches created
  summary: string                      # required — execution summary
```

**Validation rules:**
- `schema_version` must equal `1`
- `subtasks_completed` must be non-empty array (at least one subtask succeeded)
- `merge_order` must be non-empty array matching completed subtask branches
- `worktrees` must be non-empty array with valid paths
- `summary` must be present

**Example:**
```
EXECUTE_RESULT:
  schema_version: 1
  subtasks_completed:
    - task_id: add-jwt-guard
      status: completed
      branch: feature/add-jwt-guard
      files_modified: [src/auth/jwt.guard.ts]
      review_decision: PASS
    - task_id: add-refresh-token
      status: completed
      branch: feature/add-refresh-token
      files_modified: [src/auth/refresh.service.ts]
      review_decision: PASS
  merge_order: [feature/add-jwt-guard, feature/add-refresh-token]
  worktrees:
    - task_id: add-jwt-guard
      path: /Users/name/myapp-add-jwt-guard
      branch: feature/add-jwt-guard
      status: completed
    - task_id: add-refresh-token
      path: /Users/name/myapp-add-refresh-token
      branch: feature/add-refresh-token
      status: completed
  summary: 2/2 subtasks completed. JWT guard and refresh token service implemented.
```

---

## EXECUTE_CHECKPOINT

Produced by Execute Manager when budget is exceeded or partial progress needs saving.

```yaml
EXECUTE_CHECKPOINT:
  schema_version: 1                    # integer, required — always 1
  completed_so_far: object[]           # required — subtasks already done
    - task_id: string
      status: completed
      branch: string
      files_modified: string[]
  in_progress: object[]                # optional — currently running subtasks
    - task_id: string
      status: in_progress
      worktree_path: string
      agent_id: string                 # Task agent ID for potential resume
  remaining: object[]                  # required — subtasks not yet started
    - task_id: string
      status: pending
      dependencies: string[]           # task_ids that must complete first
  resume_context: object               # required — data needed to resume
    tool_calls_used: integer
    active_worktrees: string[]         # paths that still exist
    feature_branch: string
  reason: string                       # required — why checkpointing (budget, error, etc.)
  adjudication_required: boolean       # optional (v12) — true when the Execute Manager has detected an outputs gap that requires Supervisor/operator decision
  missing_outputs: object[]            # conditional (v12) — required and non-empty when adjudication_required=true
    - item: string                     # what is missing (file path, symbol, contract field)
      producing_subtask: string        # which subtask was supposed to produce it
      check_run: string                # what verification was performed (e.g., "ls", "ts-symbol-search", "schema-grep")
  adjudication_options: string[]       # conditional (v12) — required and non-empty when adjudication_required=true
                                       # typically ["A: re-queue producer", "B: insert remediation subtask",
                                       # "C: exit to Launch Pad", "D: update consumer brief"]
```

**Validation rules:**
- `schema_version` must equal `1`
- `completed_so_far` must be present (can be empty array if no subtasks done yet)
- `remaining` must be present and non-empty (otherwise use EXECUTE_RESULT)
- `resume_context` must be present with at least `feature_branch`
- `reason` must be non-empty string
- **toolset_gap rejection (hook-enforced, v12):** if `reason` cites `toolset_gap`, "Task tool unavailable", "Agent tool unavailable", or any variant claiming the spawning toolset is missing, the SubagentStop hook rejects the checkpoint. The Execute Manager spawns workers via Task and that capability is guaranteed by the harness; the actual blocker must be restated without referencing toolset availability.
- **Adjudication tri-field invariant (hook-enforced, v12):** the three fields `adjudication_required`, `missing_outputs`, and `adjudication_options` appear together (all-or-nothing). When `adjudication_required: true`, both `missing_outputs` and `adjudication_options` MUST be non-empty arrays. The SubagentStop hook (see `hooks.json` Execute Manager entry) rejects checkpoints that set the flag without populating both arrays.

---

## SUPERVISOR_RESULT

Produced by Supervisor once per task from inside Phase 4.5's completion tail (see Emission cadence below). Introduced in v11.0.0 to give a machine-readable completion record (replaces free-form markdown validation in the SubagentStop hook).

```yaml
SUPERVISOR_RESULT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — task being worked on
  status: enum [completed, completed_with_escalation, failed, checkpoint]  # required
  pr_url: string | null                # required when status in [completed, completed_with_escalation]; null for failed/checkpoint
  branch: string                       # required — feature branch name
  subtasks_completed: integer          # required — count of subtasks that passed review and merged
  subtasks_failed: integer             # required — count of subtasks that failed after retries
  heal_loop_ran: boolean              # required — did the Phase 4.5 review loop execute?
  heal_iterations: integer | null      # required — number of fix iterations that ran; null when heal_loop_ran=false
  heal_decision: enum [PASS, ESCALATED] | null  # required — null when heal_loop_ran=false (phase transition and completion tail always run; only the review-and-fix loop is gated, so no decision is produced when skipped)
  heal_fixable_issues_fixed: integer   # required — count of new+BLOCKING/HIGH issues auto-fixed across all iterations; 0 when heal_loop_ran=false
  heal_remaining_issues: integer       # required — count of new+BLOCKING/HIGH issues still unresolved in final review; 0 when heal_loop_ran=false or heal_decision=PASS
  error: string | null                 # conditional — required when status=failed
  summary: string                      # required — concise session summary
  cost_profile: enum [default, cheap] | null  # optional — null when flag not passed (equivalent to default)
  rubric_score: string | null          # optional (v12.2.0+) — "N/M" where N is non-negative (>= 0; "0/M" is the legitimate all-fail case), M is positive (>= 1), M >= N; null when no Outcomes Rubric in brief, heal_decision != PASS, or grader parse failed
  branch_base: string | null           # optional (v14.0.0+) — declared Base Branch for the run (from the brief's `Base Branch:` field). null OR absent is treated as "main" by consumers. Purpose: stacked-iteration support for `/autonomous` (iter N+1 branches from iter N's branch). Schema_version stays 1 because the field is purely additive and optional — v13 blocks without it remain valid.
  pr_state: enum [open, closed_by_loop, close_attempt_failed] | null  # optional (v14.0.0+) — records the PR state after Phase 4.5's base-mismatch cleanup path. `null` for runs where Phase 4.5 did NOT execute the base-mismatch cleanup (i.e., the overwhelming majority). `"closed_by_loop"` when the cleanup closed the PR; `"close_attempt_failed"` when the close attempt failed (operator must resolve); `"open"` is reserved for the case where the PR remained open after the path ran (informational only). Schema_version stays 1 — field is additive and optional.
  contract_conformance:                # optional (System Twin) — advisory only; NEVER changes heal_decision, NEVER blocks PR
    checked: boolean                   # false when no contracts exist / tooling unavailable
    status: enum [pass, advisory_violations, unverified, skipped]
    contracts_evaluated: integer
    violations: integer                # count of advisory violations (0 on pass)
    findings:                          # advisory
      - subsystem: string
        invariant: string
        severity: enum [info, advisory]   # by construction NEVER blocking/high
        detail: string
  benchmark_result:                    # optional (System Twin)
    ran: boolean
    status: enum [pass, regressed, improved, unverified, skipped]
    name: string
    metric: string
    value: number | null
    baseline: number | null
    delta: number | null               # value - baseline, null if no baseline
    unit: string
  ground_truth:                        # optional (System Twin / M2b slice 1a) — advisory only; NEVER changes heal_decision, NEVER blocks PR
    checked: boolean                   # false when no check source resolved / runner could not verify
    status: enum [pass, advisory_failures, unverified, skipped]
    checks_total: integer
    checks_passed: integer
    findings:                          # advisory — failing checks only
      - check: string                  # "<kind>:<target>"
        detail: string
        severity: enum [info, advisory]   # by construction NEVER blocking/high; the Phase 4.5 mapping emits "advisory" (the "info" level is reserved/permitted)
  preflight_sync: enum [clear, overlap_proceed, superseded_proceed, skipped, unverified] | null  # optional (v14.8.0+) — outcome of the Phase 1.5 PRE-FLIGHT SYNC remote-state reconciliation gate. `clear` = gate ran, no overlap/supersession found (silent path); `overlap_proceed` = OVERLAP found, user chose proceed-anyway (interactive); `superseded_proceed` = SUPERSEDED found, user chose proceed-anyway (interactive); `skipped` = `--skip-preflight-sync` short-circuited the gate; `unverified` = gh/git tooling failed and the gate degraded gracefully and continued. `null` OR absent = EITHER the gate did not run (legacy / pre-v14.8.0 resume) OR the run exited before a *proceed* classification was recorded — namely the `revise-scope` path (emits `status: checkpoint`) and the fail-closed abort path (OVERLAP/SUPERSEDED under `--non-interactive`/stdin-not-a-TTY without `--skip-preflight-sync`; emits `status: failed` with `error: "preflight_overlap_detected"`). In those two cases the gate DID run but the classification is carried in the Decisions Log entry / `error` rather than this field — read `status` + `error` to disambiguate, not `preflight_sync` alone. Schema_version stays 1 — field is additive and optional.
```

**Field semantics note:** `heal_loop_ran` reports whether the Phase 4.5 *review-and-fix loop* executed, not whether the phase itself transitioned. The phase transition and completion tail are unconditional; only the loop is gated by `--skip-self-heal` and the resume-thrash guard.

**Emission cadence:** Exactly one `SUPERVISOR_RESULT` block is emitted *per task*, from inside Phase 4.5's completion tail (after `status`/`pr_url`/heal fields are finalized). Phase 5 LOOP does NOT emit a block — it only decides whether to loop or exit. When a session processes multiple tasks via LOOP → ACQUIRE, multiple `SUPERVISOR_RESULT` blocks appear in the transcript (one per task). The SubagentStop hook validates the last block in the output; earlier blocks must also be schema-valid but are not hook-checked.

**Validation rules:**
- `schema_version` must equal `1`
- `status` must be one of: `completed`, `completed_with_escalation`, `failed`, `checkpoint`
- When `status in [completed, completed_with_escalation]`: `pr_url` must be present and non-empty
- When `status=failed`: `error` must be present and non-empty
- `heal_loop_ran` must be a boolean
- When `heal_loop_ran=false`: `heal_iterations=null`, `heal_decision=null`, `heal_fixable_issues_fixed=0`, `heal_remaining_issues=0` exactly
- When `heal_loop_ran=true`: `heal_decision` must be one of `[PASS, ESCALATED]` (NOT `SKIPPED` — skipping corresponds to `heal_loop_ran=false`), `heal_iterations` must be a non-negative integer
- `heal_fixable_issues_fixed` and `heal_remaining_issues` must be non-negative integers
- `heal_remaining_issues=0` when `heal_decision=PASS` (PASS means no BLOCKING/HIGH new issues remain)
- `heal_remaining_issues>=1` when `heal_decision=ESCALATED`
- `summary` must be present
- `rubric_score` is optional (additive in v12.2.0, schema version unchanged at 1). When present, it MUST be either `null` or a string matching the format `"N/M"` where N is a non-negative integer (`>= 0` — `"0/M"` is the legitimate all-fail case where the grader ran but every rubric item failed), M is a positive integer (`>= 1` — there is no zero-item rubric), and M ≥ N. The two non-null forms have distinct meaning: `null` = grader did not run (no rubric in brief, `heal_decision != PASS`, or grader parse failure); `"0/M"` = grader ran and scored zero items. When absent, validators MUST treat it as `null`. The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `rubric_score`.
- `branch_base` is optional (additive in v14.0.0, schema version unchanged at 1). When present, it MUST be either `null` or a non-empty string naming the declared Base Branch (e.g., `"main"`, `"feature/parent-iter"`). Absent OR `null` means the run targeted `"main"` by default. The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `branch_base` — v13 blocks without this field remain valid. Consumers reading the field MUST handle `null`/absent as equivalent to `"main"`.
- `pr_state` is optional (additive in v14.0.0, schema version unchanged at 1). When present, it MUST be either `null` or one of `"open"`, `"closed_by_loop"`, `"close_attempt_failed"`. Absent OR `null` is the normal case (Phase 4.5 base-mismatch cleanup did not execute). The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `pr_state` — v13 blocks without this field remain valid.
- `preflight_sync` is optional (additive in v14.8.0, schema version unchanged at 1). When present, it MUST be either `null` or one of `"clear"`, `"overlap_proceed"`, `"superseded_proceed"`, `"skipped"`, `"unverified"`. Absent OR `null` means EITHER the Phase 1.5 PRE-FLIGHT SYNC gate did not run (legacy emission, or a pre-v14.8.0 `--continue` resume that lands after the gate) OR the run exited before recording a *proceed* classification — the `revise-scope` checkpoint path (`status: checkpoint`) and the fail-closed abort path (`status: failed` + `error: "preflight_overlap_detected"`) both leave `preflight_sync` null and carry the classification elsewhere (Decisions Log entry / `error`). The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `preflight_sync` — pre-v14.8.0 blocks without this field remain valid (the hook does not enumerate it, mirroring the `branch_base` / `pr_state` additive precedent). Neither the `revise-scope` nor the fail-closed abort path uses a `preflight_sync` enum value; disambiguate via `status` + `error` (the abort emits `error: "preflight_overlap_detected"` — see the `preflight_overlap_detected` AUTONOMOUS_RUN `status_reason` below).

**v14.0.0 additive fields (backwards-compat):** `branch_base` and `pr_state` are purely additive optional fields. The Supervisor SubagentStop hook (see `hooks/hooks.json` matcher `ai-agent-manager-plugin:supervisor-runner`) validates the v13 field set plus optional `rubric_score`; it does NOT enumerate `branch_base` / `pr_state` and therefore accepts blocks with or without them. Existing v13 SUPERVISOR_RESULT emissions (which lack both fields) continue to validate against the hook unchanged. Schema_version remains `1` precisely because the additions are optional and additive.

**v14.8.0 additive field (backwards-compat):** `preflight_sync` is a purely additive optional field following the same precedent. The Supervisor SubagentStop hook does NOT enumerate it, so blocks with or without it validate unchanged, and pre-v14.8.0 consumers ignore it (no validation failure). Schema_version remains `1`.

**System Twin additive fields (backwards-compat):** `contract_conformance`, `benchmark_result`, and `ground_truth` are purely additive optional objects following the same `branch_base` / `pr_state` / `preflight_sync` precedent. All are **advisory only** — `contract_conformance` NEVER changes `heal_decision` and NEVER blocks the PR (its `findings[].severity` is `info` or `advisory` by construction, never `blocking`/`high`); `benchmark_result` is informational; `ground_truth` (added v14.19.0, M2b slice 1a) NEVER changes `heal_decision` and NEVER blocks the PR (its `findings[].severity` is `info` or `advisory` by construction, never `blocking`/`high`). The Supervisor SubagentStop hook does NOT enumerate any of these fields, so blocks with or without them validate unchanged, and pre-System-Twin consumers ignore them. Schema_version remains `1`. Field semantics:
- `contract_conformance.checked` is `false` (with `status: skipped` or `unverified`) when no contracts exist in `.supervisor/twin/` or the conformance tooling is unavailable; `status: pass` requires `violations: 0`; `status: advisory_violations` requires `violations >= 1` and a non-empty `findings[]`. Field names are a contract with the System Twin builder (ST3 writes, ST4 reads) — do not rename.
- `benchmark_result.delta` is `value - baseline`, or `null` when `baseline` is `null` (no prior baseline to compare against). `status: regressed` / `improved` are relative to `baseline`; `unverified` / `skipped` when the benchmark did not run or could not be measured.
- `ground_truth.checked` is `false` (with `status: skipped` or `unverified`) when no check source resolved (no brief `## Executable Acceptance` section, no `.supervisor/twin/ground-truth.json`) or the runner could not verify any check (e.g. `jq` unavailable, or only deferred `qa-executor` checks resolved); `status: pass` requires zero failing checks (and ≥1 check executed); `status: advisory_failures` requires ≥1 failing check and a non-empty `findings[]` (each `severity: info | advisory`). It is populated from the single `GROUND_TRUTH_JSON` line emitted by `scripts/run-ground-truth.sh` (see the GROUND_TRUTH_JSON schema below): `checked ⇐ ran`, `status ⇐ status`, `checks_total ⇐ checks_total`, `checks_passed ⇐ checks_passed`, `findings[] ⇐ the failing per_check entries`. Field names are a contract with the System Twin builder (ST3 writes, ST4 reads) — do not rename.
- **Hard-signal field contract:** `contract_conformance`, `benchmark_result`, and `ground_truth` (the nested-object shape, above) and the FLAT `session_end` JSONL scalar fields (`contract_conformance_status`, `contract_violations`, `benchmark_status`, `benchmark_metric`, `benchmark_value`, `benchmark_delta`, `ground_truth_status`, `ground_truth_checks_total`, `ground_truth_checks_passed`, `ground_truth_pass_rate` — see the `.supervisor/logs/{session}.jsonl` section below) are **the same hard-signal data in two shapes**. ST3 writes both; `build-insights.sh` reads the FLAT `session_end` fields (via `select(.event=="session_end")`), exactly as it reads `rubric_score` — it does NOT parse the nested SUPERVISOR_RESULT objects.

**Status mapping from heal outcome:**
- `heal_decision=PASS` OR `heal_loop_ran=false` (loop skipped via `--skip-self-heal`) → `status: completed`
- `heal_decision=ESCALATED` → `status: completed_with_escalation`
- Hard failure (merge conflict, fix task crash after retries) → `status: failed`
- Budget exhaustion → `status: checkpoint`

**Example (happy path, heal passed first try):**
```
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: add-jwt-auth
  status: completed
  pr_url: https://github.com/org/repo/pull/42
  branch: feature/add-jwt-auth
  subtasks_completed: 3
  subtasks_failed: 0
  heal_loop_ran: true
  heal_iterations: 0
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  error: null
  summary: 3/3 subtasks completed. Integration review PASS on first try. PR #42 ready for human sign-off.
  rubric_score: "5/5"
```

**Example (escalated after max iterations):**
```
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: refactor-payment-flow
  status: completed_with_escalation
  pr_url: https://github.com/org/repo/pull/87
  branch: feature/refactor-payment-flow
  subtasks_completed: 4
  subtasks_failed: 0
  heal_loop_ran: true
  heal_iterations: 3
  heal_decision: ESCALATED
  heal_fixable_issues_fixed: 7
  heal_remaining_issues: 2
  error: null
  summary: 4/4 subtasks merged. Self-heal fixed 7 issues across 3 iterations; 2 issues still unresolved (see PR comment). Human review required.
```

**Example (skip flag):**
```
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: hotfix-login
  status: completed
  pr_url: https://github.com/org/repo/pull/91
  branch: feature/hotfix-login
  subtasks_completed: 1
  subtasks_failed: 0
  heal_loop_ran: false
  heal_iterations: null
  heal_decision: null
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  error: null
  summary: 1/1 subtasks completed. Self-heal loop skipped via --skip-self-heal flag. PR #91 ready.
```

**Example (v14.0.0 — stacked iteration with explicit branch_base + pr_state):**
```
SUPERVISOR_RESULT:
  schema_version: 1
  task_id: auto-2026-05-16-iter2
  status: completed
  pr_url: https://github.com/org/repo/pull/58
  branch: feature/auto-2026-05-16-iter2
  subtasks_completed: 2
  subtasks_failed: 0
  heal_loop_ran: true
  heal_iterations: 0
  heal_decision: PASS
  heal_fixable_issues_fixed: 0
  heal_remaining_issues: 0
  error: null
  summary: Iteration 2 of stacked autonomous run; branched from feature/auto-2026-05-16-iter1. PR #58 stacks on PR #57.
  rubric_score: "5/5"
  branch_base: feature/auto-2026-05-16-iter1
  pr_state: null
```

---

## FIX_RESULT

Produced by the ad-hoc fix task that Supervisor spawns during Phase 4.5 self-heal iterations. Introduced in v11.0.0.

```yaml
FIX_RESULT:
  schema_version: 1                    # integer, required — always 1
  issues_addressed: integer            # required — count of issues the fix task resolved this iteration
  files_modified: string[]             # required — non-empty when issues_addressed > 0
  commit_sha: string                   # required — SHA of the fix commit on the feature branch
  summary: string                      # required — concise description of what was fixed
```

**Validation rules:**
- `schema_version` must equal `1`
- `issues_addressed` must be a non-negative integer
- When `issues_addressed > 0`: `files_modified` must be non-empty
- `commit_sha` must match `^[0-9a-f]{7,40}$`
- `summary` must be present

**Example:**
```
FIX_RESULT:
  schema_version: 1
  issues_addressed: 3
  files_modified: [src/auth/jwt.guard.ts, src/auth/jwt.guard.spec.ts, src/auth/types.ts]
  commit_sha: a1b2c3d
  summary: Addressed 3 HIGH-severity findings — tightened JWT validation, fixed type exports, added missing unit tests.
```

---

## QA_RESULT

Produced by QA Executor on test completion.

```yaml
QA_RESULT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — QA run identifier
  status: enum [passed, failed, partial, skipped, needs_human]  # required — needs_human signals manual intervention required (e.g., app not running, dry-run failed)
  rounds_run: string                   # optional — e.g., "1/3"
  tests_generated: integer             # required — number of test files/cases generated
  tests_run_this_session: integer      # optional — v10.3.0: tests actually executed this agent session (may differ from tests_generated if --scope/--continue)
  tests_passed: integer                # required — number passing
  tests_failed: integer                # optional — number failing (default 0)
  depth: enum [smoke, functional]      # optional — v10.3.0: test depth used
  environment: enum [local, preview, staging] # optional — v10.3.0: environment classification from Phase 3
  discovery_confidence: enum [HIGH, MEDIUM, LOW]  # optional
  discovery_warnings: string[]         # optional — v10.3.0: non-blocking warnings (e.g., "crawl_limit_hit", "infrastructure_unavailable")
  coverage_estimate: float             # optional — 0.0 to 1.0, routes/APIs tested vs discovered
  coverage: string                     # optional — v10.3.0: human-readable e.g., "routes 12/15, apis 34/40"
  coverage_weighted: float             # optional — v10.3.0: risk-adjusted coverage 0.0-1.0
  risk_score: integer                  # optional — v10.3.0: 0-100 (higher = more untested critical areas)
  interaction_coverage: string         # optional — v10.3.0: e.g., "forms 6/8, tables 3/3, modals 2/2"
  infrastructure_available: string     # optional — v7.2.0: from Phase 1.5 (e.g., "email:mailpit" or "none")
  pre_existing_tests: integer          # optional — v7.2.0: count of pre-existing tests found
  pre_existing_passing: integer        # optional — v7.2.0: count passing
  pre_existing_failing: integer        # optional — v7.2.0: count failing
  pre_existing_bugs: object[]          # optional — v7.2.0: bugs found in pre-existing test failures
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      description: string
      file: string
  pre_existing_stale: object[]         # optional — v7.2.0: stale tests needing update
    - file: string
      reason: string
  gate_audit_verdict: string           # optional — v9.0.0: from Strategist Gate Audit (e.g., "pass" or "fail")
  app_topology: object                 # optional — v10.2.0: from Phase 4 auto-detection
    ui_present: boolean                #   has browser UI
    api_style: enum [rest, graphql, mixed, none]
    client_platform: enum [web, mobile, none]
  detected_auth_method: string         # optional — v10.2.0: e.g., "oauth:auth0", "session", "api-key", "none"
  websocket_detected: boolean          # optional — v10.2.0: true if WebSocket endpoints found
  risks: object[]                      # optional — identified risk areas
    - area: string
      level: enum [HIGH, MEDIUM, LOW]
      description: string
  bugs_found: integer                  # optional — COUNT of REAL_BUG failures (>= 0)
  bugs_blocking: integer               # optional — count of BLOCKING-severity bugs
  bugs: object[]                       # optional — detailed bug list (may be omitted if bugs_found is 0)
    - id: string
      severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      description: string
      file: string                     # optional — file where bug manifests
      steps: string                    # optional — reproduction steps
  discovery_gaps: object[]             # optional — v10.3.0: DISCOVERY_GAP test failures (test was wrong, not the app)
    - description: string
      file: string
  environment_issues: object[]         # optional — v10.3.0: ENVIRONMENT_ISSUE test failures (infra/setup problem, not the app)
    - description: string
      file: string
  strategist_verdict: string           # optional — approved/rejected from Strategist
  files_created: string[]              # optional — test and discovery files created
  summary: string                      # required — max 200 tokens
  notes: string                        # optional — v10.3.0: free-form notes (e.g., "budget_exceeded", "playwright_config_auto_generated")
  error: string                        # conditional — required when status=failed
```

**Validation rules:**
- `schema_version` must equal `1`
- `tests_generated` and `tests_passed` must be non-negative integers
- `tests_passed` must be ≤ `tests_generated`
- When `status=failed`: `error` must be present
- `summary` must be present and under 200 tokens
- **Hook-enforced (in addition to schema):** when tests were actually run (i.e. `tests_generated > 0`), `coverage_estimate` must be present. The SubagentStop hook for QA Executor enforces this conditional even though the field is otherwise optional.

---

## CODE_REVIEW_RESULT

Produced by Code Reviewer agent on review completion.

```yaml
CODE_REVIEW_RESULT:
  schema_version: 3                    # integer, required — v3 adds review_mode + consistency audit fields
  review_mode: enum [diff_review, consistency_audit]  # required — plan/prompt review is an audit_focus, not a mode
  audit_focus: string[]                # required — non-empty iff review_mode=consistency_audit; else []
                                       # allowed values: mirrored_prompt, metadata, counts, docs, hooks, plan_prompt
                                       # A single audit may carry multiple focus tags.
  trigger_paths_detected: string[]     # required — subset of reviewed paths matching audit trigger surfaces
                                       # (agents/, commands/, skills/, docs/, plugin.json,
                                       # hooks.json, .supervisor/jobs/, README.md, CLAUDE.md,
                                       # .claude-plugin/README.md, SKILLS_INDEX.md). Empty = no trigger fired.
                                       # INVARIANT: non-empty ⇒ review_mode MUST equal "consistency_audit".
  scope_expanded: string[]             # required — files added beyond the original diff; [] if no expansion
  files_checked: string[]              # required, non-empty — all files actually read during review
  consistency_checks:                  # required when review_mode=consistency_audit; omit otherwise
    mirrored_prompts:   enum [pass, fail, not_applicable]
    version_strings:    enum [pass, fail, not_applicable]   # authoritative-tier only
    counts:             enum [pass, fail, not_applicable]
    workflow_alignment: enum [pass, fail, not_applicable]
    hooks_parity:       enum [pass, fail, not_applicable]   # advisory; fail cannot raise severity > LOW
  consistency_summary: string          # required when review_mode=consistency_audit
  decision: enum [PASS, FAIL, NEEDS_HUMAN]  # required
  issues: object[]                     # required (can be empty for PASS)
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      category: enum [new, pre_existing, nit, drift]  # drift added in v3
      drift_kind: enum [version_authoritative, version_secondary, mirrored_prompt,
                        count, workflow, hooks_parity, wording]  # required when category=drift
      file: string                     # file path
      line: integer                    # optional — line number
      description: string              # what's wrong
      suggestion: string               # optional — how to fix
  pattern_proposals: object[]          # optional — patterns for CLAUDE.md
    - pattern: string
      file: string
      description: string
  summary: string                      # required — concise review summary
```

**Validation rules (schema_version: 3):**
- `schema_version` must equal `3` (v2 still accepted for backward compatibility / legacy agent memory)
- `review_mode` must be one of: `diff_review`, `consistency_audit`
- `audit_focus` is required; non-empty iff `review_mode == consistency_audit`; each element ∈ {mirrored_prompt, metadata, counts, docs, hooks, plan_prompt}
- `trigger_paths_detected` is required (may be empty)
- **Cross-field invariant:** if `trigger_paths_detected` is non-empty → `review_mode` MUST equal `consistency_audit`
- `files_checked` must be a non-empty array
- `scope_expanded` must be present (may be empty for `diff_review`)
- When `review_mode == consistency_audit`: `consistency_checks` object with all 5 sub-keys present; `consistency_summary` non-empty
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- Each issue must include `category` ∈ {new, pre_existing, nit, drift}
- When `category == drift`: `drift_kind` required
- **`drift_kind` severity caps are enforced** (issues violating these caps are rejected):
  - `drift_kind ∈ {count, version_secondary}` → severity MUST be `≤ MEDIUM`
  - `drift_kind ∈ {hooks_parity, wording}` → severity MUST be `≤ LOW`
  - `drift_kind ∈ {version_authoritative, mirrored_prompt, workflow}` → no cap
- When `decision=FAIL`: `issues` must contain at least one issue with `category ∈ {new, drift}` AND severity ∈ {BLOCKING, HIGH}. Because of the caps above, `count`, `version_secondary`, `hooks_parity`, and `wording` drift cannot satisfy FAIL on their own
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- `summary` must be present

**Validation rules (schema_version: 2, legacy):**
- `schema_version` must equal `2`
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- When `decision=FAIL`: `issues` must contain at least one `new` issue with BLOCKING or HIGH severity
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- Each issue must include `category` ∈ {new, pre_existing, nit}
- Only `new` issues with BLOCKING/HIGH severity can trigger FAIL
- `summary` must be present

**Migration notes (v2 → v3):**
- v3 introduces review modes and a repo-consistency audit contract. Existing v2 producers remain valid.
- The `drift` category and `drift_kind` enum make consistency-audit findings first-class issues rather than free-text notes, and the severity caps prevent advisory drift (counts, hooks parity, wording) from blocking PRs.
- Plan/prompt review is represented as `audit_focus: plan_prompt` (not a distinct `review_mode`), so a single audit touching both prompts and metadata emits one result with multiple focus tags instead of requiring mode precedence rules.
- The `trigger_paths_detected` ↔ `review_mode` cross-field invariant is what makes the new hook enforcement possible: the reviewer is accountable to its own self-report of which trigger surfaces the diff touched.

---

## PLAN_REVIEW_RESULT

Produced by Plan Reviewer agent when validating a Supervisor-Ready Brief (Launch Pad Phase 5.5).

```yaml
PLAN_REVIEW_RESULT:
  schema_version: 1                    # integer, required
  decision: enum [PASS, FAIL, NEEDS_HUMAN]  # required
  issues: object[]                     # required (can be empty for PASS)
    - severity: enum [BLOCKING, HIGH, MEDIUM, LOW]
      section: string                  # brief section name (e.g., "Subtask Structure", "File Impact Map")
      category: string                 # optional — issue category (e.g., "dep_graph" for Criterion 12 violations, "file_path" for missing files, "executable_acceptance" for Criterion 14 cmd:/bare-shell trust-surface findings); free-form, but use canonical names where defined
      description: string              # what's wrong
      suggestion: string               # optional — how to fix
  summary: string                      # required — concise review summary
```

**Validation rules:**
- `schema_version` must equal `1`
- `decision` must be one of: `PASS`, `FAIL`, `NEEDS_HUMAN`
- When `decision=FAIL`: `issues` must contain at least one issue with BLOCKING or HIGH severity
- When `decision=NEEDS_HUMAN`: `issues` must be non-empty
- `section` must reference a valid brief section name
- `category` is optional but recommended; when present, prefer canonical names — `dep_graph` for Criterion 12 (provides/requires) violations, `file_path` for missing-file violations, `feasibility` for Criterion 11 issues, `executable_acceptance` for Criterion 14 (`## Executable Acceptance` `cmd:`/bare-shell bullets)
- `summary` must be present

**Severity mapping for plan review:**
- BLOCKING: Missing/nonexistent file paths, missing required brief sections
- HIGH: Incorrect dependencies, unsafe parallelism (false LAUNCHABLE), logic errors
- MEDIUM: Vague acceptance criteria, missing skill references, incomplete risk assessment
- LOW: Style improvements, optional enhancements

---

## CONTEXT_KEEPER_STATE

Schema for `.supervisor/state.md` managed by Context-Keeper.

```yaml
version: integer                       # required — monotonic counter, increments on every write
current_phase: enum [INIT, ACQUIRE, PLAN, EXECUTE, FINALIZE, SELF_HEAL, LOOP]  # required
session_id: string                     # required — unique session identifier
task_id: string                        # required — current task being worked on
task_title: string                     # optional — human-readable task description
branch: string                         # required after ACQUIRE — feature branch name
config:
  max_workers: integer                 # default 2
  mode: enum [parallel, sequential]    # default parallel
  cost_profile: enum [default, cheap]  # optional — default "default"; set from --cheap flag at INIT
active_subtasks: object[]              # required during EXECUTE
  - id: string
    status: enum [pending, in_progress, completed, failed]
    worktree_path: string              # optional — only for parallel mode
    branch: string                     # optional — subtask branch
    agent_id: string                   # optional — Task agent ID
completed_subtasks: string[]           # subtask IDs that are done
failed_subtasks: string[]              # subtask IDs that failed
worktrees: object[]                    # active worktree tracking
  - task_id: string
    path: string
    branch: string
    status: enum [active, merged, cleaned, failed]
agents_running: object[]               # currently spawned agents
  - agent_type: string                 # e.g., "worker", "code-reviewer"
    task_id: string
    started_at: timestamp
self_heal_resume_count: integer        # optional — default 0; increments only on resumes that actually execute the code-reviewer Task in Phase 4.5 (first loop iteration), NOT on every --continue landing in SELF_HEAL. Phase 4.5 invariant-violation resumes (code-reviewer never invoked AND --skip-self-heal not set) deliberately do NOT increment, so they cannot age into a self_heal_resume_thrash escalation. Resets to 0 in the SELF_HEAL completion tail on the three completion exit paths (PASS, ESCALATED, or loop-skipped via --skip-self-heal); the invariant-violation guard (step 0) exits with status: failed before reaching the reset step and deliberately does NOT reset, preserving prior legitimate reviewer-reaching counts. Thrash guard: if the counter reaches 3, Supervisor aborts the loop and escalates with self_heal_resume_thrash reason. Lazy-added on first SELF_HEAL resume that runs the reviewer; mutated via record_self_heal_resume operation; read non-mutatively via query(section: session).
last_updated: timestamp                # required — ISO 8601
```

**Phase note:** `SELF_HEAL` (added in v11.0.0) is the post-FINALIZE holistic review + bounded fix loop. Entered after PR creation; exits to LOOP after PASS or ESCALATED outcome, or when `--skip-self-heal` short-circuits the review loop (completion tail still runs).

**Validation rules:**
- `version` starts at 1 and monotonically increases on every write
- `current_phase` must be one of: `INIT`, `ACQUIRE`, `PLAN`, `EXECUTE`, `FINALIZE`, `SELF_HEAL`, `LOOP`
- `last_updated` must be in ISO 8601 format
- `active_subtasks` required when `current_phase = EXECUTE`
- `branch` required after `ACQUIRE` phase (all subsequent phases)
- `session_id` and `task_id` must be non-empty strings

---

## SYSTEM_CONTRACT

Per-subsystem artifact in the **System Twin** contract store. One file per subsystem at
`.supervisor/twin/contracts/<subsystem-id>.md` (the `<subsystem-id>` is the sanitized filename;
the logical `subsystem` name is preserved verbatim in the artifact body). Written **exclusively**
by `scripts/write-system-contract.sh`, read via `scripts/read-system-contract.sh` (the read-side
provenance gate). This is the **authoritative definition** of the contract body.

`.supervisor/twin/` is an ADVISORY artifact store like `.supervisor/memory/` — **subordinate to
the human-authored CLAUDE.md** and NEVER an enforcement boundary. Contracts are propose-only;
any conformance check against them (`SUPERVISOR_RESULT.contract_conformance`) is advisory and
NEVER blocks a PR or changes a heal decision. See `docs/ARCHITECTURE_CONTRACTS.md` §"System Twin
homing contract" for the sole-writer / pinned-CWD / worktree-guard enforcement model.

```yaml
SYSTEM_CONTRACT:
  schema_version: 1
  subsystem: string            # logical name or path, e.g. "scripts/build-insights.sh" or "supervisor-phase45"
  invariants: [string]         # properties that must hold
  dependencies: [string]       # DIRECTIONAL "depends-on" edges: subsystems/files THIS subsystem depends on.
                               # These are the forward blast-radius edges (Pillar 1 reads these). The REVERSE
                               # direction ("depended-on-by" / derived dependents) is NOT stored — it is
                               # computed on demand by scripts/twin-graph.sh, which scans every verified
                               # contract's dependencies to find who points back at this subsystem.
  behavioral_specs: [string]   # observable behaviors
  incident_history: [ {date, kind, summary, source} ]
                               # OPTIONAL/ADDITIVE advisory blast-radius history; bounded (the Phase 4.5
                               # builder keeps the most recent 5, chronological oldest-first) + deduped. Each entry:
                               #   date    — ISO 8601 timestamp of the incident
                               #   kind    — one of: conformance_violation | self_heal_fix | other
                               #   summary — short string describing the incident
                               #   source  — the builder session id that recorded it
                               # Append-only by the Phase 4.5 contract builder, and only for THIS run's incidents.
  provenance:
    derived_from: string       # commit SHA or "git diff origin/main...HEAD"
    written_at: string         # ISO 8601
    source: string             # builder session id / agent
    content_hash: string       # OPTIONAL/informational only. The AUTHORITATIVE content_hash lives in
                               # the .provenance.jsonl ledger (sha256 of the contract-file bytes), NOT
                               # in the body — a file cannot contain its own hash. See note below.
```

**Store / provenance notes:**
- The artifact body above is held verbatim in the contract file. A separate hash-chained
  provenance ledger at `.supervisor/twin/.provenance.jsonl` carries, per write, a
  `{subsystem, prev_hash, content_hash, source, action, written_at}` entry (mirroring
  `.supervisor/memory/.provenance.jsonl`). The **authoritative `content_hash` lives in the ledger,
  not in the artifact body** — `write-system-contract.sh` computes it as `sha256(contract-file-bytes)`
  at write time and records it only in the ledger entry. The read-side gate (`read-system-contract.sh`)
  **recomputes `sha256(contract-file-bytes)` and matches it against the ledger's `content_hash`** to
  decide whether a contract is verified. (A file cannot contain its own hash, so the body's
  `provenance.content_hash` field is at most an informational copy and is never what the gate checks.)
  Un-provenanced or post-chain-break contracts are dropped (and logged to `.supervisor/logs/twin.log`),
  never emitted.
- **Subsystem ID convention (writer ⇄ reader MUST agree).** The `subsystem` id is the lookup key,
  so the builder (writer) and Launch Pad (reader) must derive the *same* id for the same subsystem —
  otherwise a read silently misses (graceful fallback emits nothing). Convention: use the
  **repo-root-relative path** for a file-backed subsystem (e.g. `scripts/build-insights.sh`) and a
  stable **logical name** for a cross-file concern (e.g. `supervisor-phase45`). The store *filename*
  is a sanitized form of this id (`/` → `-`, etc.); the logical id is preserved verbatim in the body
  and in the provenance `subsystem` field. Do not abbreviate (`build-insights` ≠ `scripts/build-insights.sh`).
- `schema_version` stays `1`. The artifact is propose-only and advisory; downstream subtasks
  (ST2 read-path, ST3 prove/hard-signal, ST4 measure-path) treat this schema as source of truth.
- **`incident_history` is additive (a contract written WITHOUT it stays valid).** Following the
  same additive precedent as the foundation slice, `schema_version` **stays `1`** — adding this
  field does NOT bump the version, and any reader/conformance check MUST treat a missing
  `incident_history` as the empty list. Entries are **advisory / propose-only**, **bounded + deduped**,
  and are only ever **appended by the Phase 4.5 contract builder for THIS run's incidents**
  (a conformance violation it observed, or a self-heal fix it applied) — never backfilled, never
  authoritative, and never a gate. `dependencies[]` remains directional "depends-on" edges; the
  reverse ("depended-on-by") is derived live by `scripts/twin-graph.sh` and is intentionally NOT
  persisted in the contract.

---

## `session_end` JSONL hard-signal fields (System Twin)

The System Twin hard signal is emitted not only as the nested `SUPERVISOR_RESULT.contract_conformance`
/ `.benchmark_result` objects (see SUPERVISOR_RESULT, above) but ALSO as **FLAT scalar fields on the
`session_end` event** in the per-session log `.supervisor/logs/{session}.jsonl`. This is what
`scripts/build-insights.sh` aggregates — it reads these via `select(.event=="session_end")`,
exactly like it already reads `rubric_score`. It does NOT parse the nested SUPERVISOR_RESULT objects.

```jsonl
{"event":"session_end", ...,
 "contract_conformance_status":"pass|advisory_violations|unverified|skipped",
 "contract_violations": 0,
 "benchmark_status":"pass|regressed|improved|unverified|skipped",
 "benchmark_metric":"<string>",
 "benchmark_value": <number|null>,
 "benchmark_delta": <number|null>,
 "ground_truth_status":"pass|advisory_failures|unverified|skipped",
 "ground_truth_checks_total": 0,
 "ground_truth_checks_passed": 0,
 "ground_truth_pass_rate":"<M/N>"}
```

> The session_end record carries both an `event` and a (legacy) `type` key with the same value
> `"session_end"`. **`event` is canonical going forward** — `build-insights.sh` filters on `.event`;
> the duplicate `type` is retained only for backward-compatibility with older logs. New consumers
> should read `.event`.

**Hard-signal field contract (the same data in two shapes):** the FLAT `session_end` fields above
and the nested `SUPERVISOR_RESULT.contract_conformance` / `.benchmark_result` objects carry **the
same hard-signal data in two shapes**. ST3 writes both; the field correspondence is:
- `contract_conformance_status` ⇔ `contract_conformance.status`
- `contract_violations` ⇔ `contract_conformance.violations`
- `benchmark_status` ⇔ `benchmark_result.status`
- `benchmark_metric` ⇔ `benchmark_result.metric`
- `benchmark_value` ⇔ `benchmark_result.value` (`null` when not measured)
- `benchmark_delta` ⇔ `benchmark_result.delta` (`null` when no baseline)
- `ground_truth_status` ⇔ `ground_truth.status` (System Twin / M2b slice 1a, added v14.19.0)
- `ground_truth_checks_total` ⇔ `ground_truth.checks_total`
- `ground_truth_checks_passed` ⇔ `ground_truth.checks_passed`
- `ground_truth_pass_rate` (string `"M/N"`) ⇔ the runner's `pass_rate`

`build-insights.sh` (ST4 / measure-path) reads the FLAT `session_end` fields — these field names
are a contract with ST3 (writer) and ST4 (aggregator); do not rename them. The flat fields are
additive to the `session_end` event; events without them remain valid (a reader treats absent
fields as "not reported this session"; the `ground_truth_*` fields, when absent, are treated as
`"skipped"`).

> **ST4 aggregation status (M2b slice 1a):** `build-insights.sh` currently aggregates the
> `contract_*` / `benchmark_*` flat fields. The `ground_truth_*` flat fields are **written now**
> (forward-compatible) but their dashboard aggregation is a **deliberate follow-up** — slice 1a
> ships the write side; wiring `ground_truth_*` into `build-insights.sh` is left to a later slice so
> this change set does not touch the insights-owned files.

---

## EVAL_RESULT (System Twin eval harness)

Emitted by `scripts/run-eval.sh` — the System Twin **eval instrument** (M2a). It is a
deterministic runner/scorer that measures plugin *output quality* against a fixed corpus of tasks
under `scripts/eval-corpus/` (one self-contained dir per task, each carrying an executable
`check.sh` whose exit code is the per-task verdict). The script prints a human/grep per-task block
plus a `Pass rate: M/N` line, AND exactly ONE machine-readable line `EVAL_RESULT: {...}` (jq-built
for injection safety). The harness ALWAYS exits 0.

The **`pass_rate` (M/N) is the fitness-function signal** — the headline metric tracked
release-over-release. The runner is deterministic: the same corpus + same checks produce identical
`tasks_total` / `tasks_passed` / `pass_rate` / `per_task` every run. The **determinism invariant
covers those tallies/per_task only**; the contextual `commit` / `date` fields legitimately vary
per run and are explicitly NOT part of the invariant.

```json
EVAL_RESULT: {
  "schema_version": 1,
  "tasks_total": 4,
  "tasks_passed": 4,
  "pass_rate": "4/4",
  "per_task": [ {"id": "doc-currency-green", "status": "pass"}, ... ],
  "commit": "268a6be",
  "date": "2026-06-06T17:35:45Z",
  "status": "ok"
}
```

**Field contract (schema_version: 1):**
- `schema_version` — integer, required, always `1`.
- `tasks_total` — integer; count of corpus tasks discovered (dirs under the corpus carrying an
  executable `check.sh`). `0` in the fail-safe path.
- `tasks_passed` — integer; count whose `check.sh` exited `0`.
- `pass_rate` — string `"M/N"` (e.g. `"4/4"`). The **fitness-function signal trackable
  release-over-release**. `"0/0"` in the fail-safe path.
- `per_task` — array of `{id, status}` objects, one per discovered task, in deterministic sorted
  order. `id` is the task-dir basename; `status` is one of `pass | fail` (a non-zero `check.sh` is
  a normal `fail` tally, never a script crash). `[]` in the fail-safe path.
- `commit` — short commit SHA at run time, or `"unknown"` if `git` is unavailable. **Contextual —
  NOT part of the determinism invariant.**
- `date` — ISO 8601 UTC timestamp at run time, or `"unknown"`. **Contextual — NOT part of the
  determinism invariant.**
- `status` — one of:
  - `ok` — normal: the corpus ran and the tallies are real.
  - `unverified` — fail-safe: the corpus dir is missing OR `jq` is unavailable, so the eval could
    not run. Emitted with `tasks_total: 0`, `tasks_passed: 0`, `pass_rate: "0/0"`, `per_task: []`
    (mirroring `run-benchmark.sh`'s fail-safe — an eval that cannot run must never break its
    caller).

**Scope honesty (M2a vs M2b):** this is the eval **instrument** (M2a, shipped v14.17.0) — a fitness
function over an output-quality corpus. It is **DISTINCT from the canary benchmark**
(`BENCHMARK_JSON` / `scripts/run-benchmark.sh`), which validates the `session_end` hard-signal
pipeline and is named/stored separately on purpose ("eval" ≠ "benchmark"). The eval harness does
**NOT** auto-run the full Launch Pad→Supervisor agent loop in CI against the corpus, and does **NOT**
wire ground-truth execution into Supervisor Phase 4.5 — **both are explicit M2b follow-ups**
(deferred). See `scripts/run-eval.sh` (the runner/scorer) and `scripts/eval-corpus/` (the corpus +
per-task `check.sh` checks), and `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` §4 (M2) for milestone status.

---

## GROUND_TRUTH_JSON (System Twin ground-truth runner)

Emitted by `scripts/run-ground-truth.sh` — the System Twin **ground-truth instrument** (M2b slice
1a). It resolves a set of project-declared **executable acceptance checks**, runs each one (exit 0 =
pass, non-zero = fail), and emits a single hard PASS/FAIL signal. The script prints a human/grep
per-check block plus a `Checks passed: M/N` line, AND exactly ONE machine-readable line
`GROUND_TRUTH_JSON: {...}` (jq-built for injection safety). The runner ALWAYS exits 0 (a check's
non-zero exit is a normal `fail` tally, never a script crash). **Trust boundary (not a sandbox):** the
runner ITSELF performs no repo writes and makes no network calls, but a `cmd:` check runs an arbitrary
`bash -c` with full shell privileges — the "no writes / no network" property holds for the runner, NOT
for the trusted-by-construction checks it executes. Because Phase 4.5 runs this automatically and
unattended (incl. under `/autonomous`, where the `## Executable Acceptance` section is machine-authored
by Launch Pad), `cmd:` bullets are a trust-sensitive surface to review at Plan Review; `corpus-task`
ids are constrained to a single path segment so they cannot escape `eval-corpus`. **Safety valve:**
`--no-cmd` (or `GROUND_TRUTH_NO_CMD=1`) skips `cmd:`/bare checks entirely (recorded `unverified`,
reason `cmd_disabled` — never executed); `corpus-task:`/`qa-executor:` are unaffected. Supervisor
Phase 4.5 passes `--no-cmd` on the unattended/`--non-interactive` (`/autonomous`) path so a
machine-authored `cmd:` bullet never runs arbitrary shell with no human in the loop — the interim
guard until the prompt-level Plan Reviewer control lands (M2b slice 1b; see
`docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` §7). It is consumed by
Supervisor Phase 4.5, which maps it onto the
`SUPERVISOR_RESULT.ground_truth` object and the flat `ground_truth_*` `session_end` fields (advisory
only — NEVER changes `heal_decision`, NEVER blocks the PR).

```json
GROUND_TRUTH_JSON: {
  "schema_version": 1,
  "ran": true,
  "status": "pass",
  "checks_total": 2,
  "checks_passed": 2,
  "pass_rate": "2/2",
  "per_check": [
    {"kind": "cmd", "target": "scripts/test-foo.sh", "status": "pass"},
    {"kind": "corpus-task", "target": "version-consistent", "status": "pass"}
  ],
  "commit": "268a6be",
  "date": "2026-06-07T15:43:00Z"
}
```

**Field contract (schema_version: 1):**
- `schema_version` — integer, required, always `1`.
- `ran` — boolean; `true` when ≥1 resolved check actually executed (a verifiable pass/fail), `false`
  on the no-source / no-`jq` / all-deferred fail-safe paths.
- `status` — one of:
  - `pass` — ≥1 check executed and passed, and ZERO checks failed (deferred `qa-executor` checks may
    coexist; they never block a pass).
  - `advisory_failures` — ≥1 resolved check exited non-zero (a `per_check` `fail` is present).
  - `unverified` — fail-safe tooling path: `jq` unavailable, OR checks resolved but NONE could be
    verified (zero passes AND zero fails AND ≥1 deferred — honest: nothing was actually verified).
  - `skipped` — no check source resolved (no `--check`, no `--brief` `## Executable Acceptance`
    section, no `--checks-file`/stdin, no `.supervisor/twin/ground-truth.json`). `ran:false`, `0/0`,
    empty `per_check`.
- `checks_total` — integer; count of resolved checks. `0` on the `skipped` (no source) and no-`jq`
  paths; **≥1 on the all-deferred `unverified` path** (a deferred `qa-executor` check is resolved and
  counts toward the total even though it executes nothing).
- `checks_passed` — integer; count whose check exited `0`.
- `pass_rate` — string `"M/N"` (e.g. `"2/2"`). `"0/0"` on the `skipped`/no-`jq` paths; the
  all-deferred `unverified` path reports the real `"0/N"` (N = the deferred checks counted in
  `checks_total`).
- `per_check` — array of `{kind, target, status, reason?}` objects, one per resolved check. **Order is
  source-dependent:** explicit `--check` / `--brief` / `--checks-file` preserve declaration order, but
  the `.supervisor/twin/ground-truth.json` fallback is `LC_ALL=C`-sorted for determinism — downstream
  readers should not assume declaration order in the fallback case.
  - `kind` — one of `cmd | corpus-task | qa-executor`.
  - `target` — the shell command (`cmd`), corpus task-id (`corpus-task`), or QA target
    (`qa-executor`).
  - `status` — one of `pass | fail | unverified` (a non-zero exit is a normal `fail` tally, never a
    crash).
  - `reason` — optional short string. Known values: `corpus_task_not_found` (missing task dir /
    `check.sh` — a missing dogfood target is a real `fail`), `corpus_task_invalid_id`, `empty_cmd_target`
    (a bare `cmd:` with no command), `cmd_disabled` (a `cmd:`/bare check skipped under `--no-cmd` /
    `GROUND_TRUTH_NO_CMD=1`), and `qa_executor_dispatch_deferred_m2b_1b` (the deferred `qa-executor` kind).
- `commit` — short commit SHA at run time, or `"unknown"`. **Contextual — NOT part of any determinism
  invariant.**
- `date` — ISO 8601 UTC timestamp at run time, or `"unknown"`. **Contextual.**

**Distinct from EVAL_RESULT and BENCHMARK_JSON:** "ground-truth" ≠ "eval" ≠ "benchmark". `EVAL_RESULT`
(`scripts/run-eval.sh`) is the **eval instrument** — a fitness function scoring plugin output quality
over a fixed corpus. `BENCHMARK_JSON` (`scripts/run-benchmark.sh`) is the **canary benchmark** —
validating the `session_end` hard-signal fixtures. `GROUND_TRUTH_JSON` (`scripts/run-ground-truth.sh`)
executes the *actual acceptance checks a brief/project declares*. The three are kept distinct by name,
dir, and intent.

**Scope honesty (M2b slice 1a vs deferred):** slice 1a (shipped v14.19.0) wires the **generic
executable-acceptance path** — `cmd:`/bare shell checks and `corpus-task:` checks resolved from a
brief's `## Executable Acceptance` section (or `.supervisor/twin/ground-truth.json`) and run after the
Code Reviewer pass in Phase 4.5. The `qa-executor:` kind is RECOGNIZED but **DEFERRED to slice 1b**
(per-check `unverified`, reason `qa_executor_dispatch_deferred_m2b_1b`; it spawns nothing). Auto-running
the full Launch Pad→Supervisor agent loop in CI against the corpus, and wiring ground-truth into a
ground-truth-execution gate, are **part-2 follow-ups** (deferred). See `scripts/run-ground-truth.sh`
and `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` §4 (M2) for milestone status.

### `## Executable Acceptance` (brief convention)

The optional `## Executable Acceptance` section in a brief is a list of `- ` bullets, each either a
raw shell command or a `<kind>: <target>` line where `kind ∈ {cmd, corpus-task, qa-executor}`:
- `cmd: <shell>` (or a **bare** bullet with no recognized `kind:` prefix) — a shell command run in the
  caller's CWD (Supervisor Phase 4.5 pins repo-root CWD); exit `0` = pass. An empty command (a bare
  `cmd:`) is a `fail` (reason `empty_cmd_target`), never a false pass. A command that itself starts
  with a dash MUST use the `cmd:` prefix (`cmd: -flag …`) — a *bare* leading-dash bullet would have its
  dash stripped as a bullet marker at ingestion.
- `corpus-task: <id>` — runs `scripts/eval-corpus/<id>/check.sh` via `bash` from the task dir (like
  `run-eval.sh`, though without run-eval's present-but-non-executable-`check.sh` fail guard — here the
  check is always invoked through `bash`); exit `0` = pass. A missing task dir / `check.sh` is a `fail`
  (reason `corpus_task_not_found`), not a silent drop. The `<id>` is a single path segment (a `/` or
  `..` is rejected as `corpus_task_invalid_id`).
- `qa-executor: <target>` — RECOGNIZED but DEFERRED to slice 1b (per-check `unverified`).

Supervisor Phase 4.5 passes this section to `run-ground-truth.sh` via `--brief <brief_path>` (falling
back to `.supervisor/twin/ground-truth.json` when the brief has no such section).

**Authoring convention (trust boundary).** A **machine-authored** brief (Launch Pad, especially under
`/autonomous`) MUST emit `corpus-task:` bullets ONLY — never `cmd:`/bare shell (`agents/launch-pad.md`
Phase 5; `skills/supervisor-readiness/SKILL.md` §"`## Executable Acceptance`"). `cmd:` bullets are
reserved for human authorship. Plan Reviewer **Criterion 14** (`agents/plan-reviewer.md`) surfaces any
`cmd:`/bare bullet that appears in a brief as a LOW `executable_acceptance` issue (advisory today;
escalates at M3). On the unattended/`--non-interactive` path Supervisor passes `run-ground-truth.sh
--no-cmd`, so a `cmd:` bullet there is skipped (`unverified`, reason `cmd_disabled`) and never runs.
See `docs/SPIKES/SYSTEM_TWIN_ROADMAP.md §7`.

---

## POSTMORTEM_RESULT (PR review-churn analyzer)

Appended by the `/pr-postmortem` command (governed by `skills/pr-postmortem/SKILL.md`) — the read-only
on-demand **PR review-churn root-cause analyzer**. After a PR has absorbed multiple rounds of post-PR
review-and-fix, the command gathers the PR's metadata + review threads + feature-branch diff (via
`scripts/pr-postmortem-gather.sh`), buckets each review round into a reproducible root-cause class, and
attributes it to a flow stage. It prints a human-readable root-cause report, then appends **exactly one**
jq-built JSONL line to `.supervisor/postmortem/results.jsonl` under the current working `.supervisor/`
(never the analyzed repo).

It is **advisory / diagnostic only** — it never writes code, never gates, never blocks the PR. The append
is best-effort and fail-safe (a `jq`/IO failure prints one warning and still exits 0; the report is already
printed). There is **no hook validator** (mirroring EVAL_RESULT / GROUND_TRUTH_JSON — the command is the
main agent of its own session). The accumulated trend file is the **seed corpus for a future synthetic eval
harness** (the deferred M2b part-2b headless-`claude` evaluator).

```json
{
  "schema_version": 1,
  "ts": "2026-06-10T12:00:00Z",
  "repo": "owner/repo",
  "number": 43,
  "agent_generated_guess": true,
  "review_rounds": 4,
  "additions": 312,
  "deletions": 27,
  "changed_files": 9,
  "categories": [ {"round": 1, "class": "validation_parity", "self_heal_miss": true, "flow_stage": "self_heal", "evidence": "backend missing the numeric guard the frontend has"}, ... ],
  "self_heal_misses": 3,
  "flow_stages": { "launch_pad": 0, "worker": 1, "self_heal": 3, "unknowable": 0 },
  "summary": "4 rounds; 3 were self-heal misses (validation parity + falsy coercion)"
}
```

**Field contract (schema_version: 1):**
- `schema_version` — integer, required, always `1`.
- `ts` — ISO 8601 UTC timestamp at append time.
- `repo` — `owner/repo` of the analyzed PR (from gather).
- `number` — integer PR number (from gather).
- `agent_generated_guess` — boolean; best-effort agent-PR heuristic (from gather).
- `review_rounds` — integer; total review-and-fix rounds (from gather).
- `additions` / `deletions` / `changed_files` — integers; PR size (from gather).
- `categories` — array of per-round objects `{round, class, self_heal_miss, flow_stage, evidence}`, one
  per review round, classifying each into a root-cause class and the flow stage that should have caught it.
- `self_heal_misses` — integer; count of rounds flagged `self_heal_miss` (i.e. Phase 4.5 should have
  caught the class but didn't).
- `flow_stages` — object tallying rounds per stage `{launch_pad, worker, self_heal, unknowable}`.
- `summary` — short human-readable one-liner.

**Append-only / write-only:** the file is the seed corpus for the deferred synthetic eval harness; it is
never read back by the skill and lives under the current working `.supervisor/`, never the analyzed repo.
See `skills/pr-postmortem/SKILL.md` (the analysis protocol + miss-class taxonomy) and
`scripts/pr-postmortem-gather.sh` (the read-only gather).

---

## QA_SESSION

Schema for `.qa-session/plan.json` and `.qa-session/coverage.json` managed by QA Executor during session-based testing.

### plan.json

```yaml
QA_SESSION_PLAN:
  schema_version: 1                    # integer, required — always 1
  created: string                      # required — ISO date (YYYY-MM-DD)
  app_url: string                      # required — base URL of the application
  total_routes: integer                # required — total routes discovered
  total_apis: integer                  # required — total API endpoints discovered
  discovery_confidence: enum [HIGH, MEDIUM, LOW]  # required
  app_topology: object                 # optional — v10.2.0: from Phase 4 auto-detection
    ui_present: boolean
    api_style: enum [rest, graphql, mixed, none]
    client_platform: enum [web, mobile, none]
  auth_method: string                  # optional — v10.2.0: e.g., "oauth:auth0", "session"
  scopes: object[]                     # required — non-empty array of feature scopes
    - name: string                     # required — scope identifier (e.g., "auth", "tournaments")
      routes: string[]                 # required — route paths in this scope
      apis: string[]                   # required — API endpoints in this scope (e.g., "POST /api/auth/login")
      risk: enum [HIGH, MEDIUM, LOW]   # required — highest risk route in scope
      priority: integer                # required — 1 = highest priority
      status: enum [pending, in_progress, completed, failed, skipped]  # required
      estimated_tests: integer         # required — estimated test count for this scope
      completed_at: string             # optional — ISO timestamp when scope was completed
```

**Validation rules:**
- `schema_version` must equal `1`
- `scopes` must be non-empty array
- Each scope must have unique `name`
- `priority` must be unique across scopes
- `status` starts as `pending` for all scopes

### coverage.json

```yaml
QA_SESSION_COVERAGE:
  schema_version: 1                    # integer, required — always 1
  last_updated: string                 # required — ISO timestamp
  sessions_completed: integer          # required — number of scope sessions run
  routes_tested: integer               # required — cumulative unique routes tested
  routes_total: integer                # required — total routes in plan
  apis_tested: integer                 # required — cumulative unique APIs tested
  apis_total: integer                  # required — total APIs in plan
  scopes_completed: string[]           # required — list of completed scope names
  scopes_remaining: string[]           # required — list of pending scope names
```

**Validation rules:**
- `routes_tested` must be ≤ `routes_total`
- `apis_tested` must be ≤ `apis_total`
- `scopes_completed` + `scopes_remaining` must equal total scope count

### QA_RESULT Session Extensions

When QA Executor runs with `--plan`, `--scope`, or `--continue`, the QA_RESULT includes additional fields:

```yaml
# Additional fields in QA_RESULT for session mode:
  depth: enum [smoke, functional]      # required — test depth used
  scope: string                        # optional — scope name (null for --plan)
  session_id: string                   # optional — unique session identifier
  cumulative_coverage: object          # optional — from coverage.json
    routes_tested: integer
    routes_total: integer
    apis_tested: integer
    apis_total: integer
    scopes_completed: integer
    scopes_total: integer
```

---

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
        "supervisor_option_c_detected"
      ]
      source: enum [launch_pad_phase_6, launch_pad_no_go, launch_pad_plan_review, autonomous_rubric_gate, supervisor_adjudication]
  rubric_final_score: string | null    # required — last iteration's rubric_score (null when no rubric in requirement OR when total_iterations == 0)
```

**`status_reason` enum** (documented as a closed set; new values require updating both this schema and `skills/autonomous-loop/SKILL.md`). The mapping between `status` and the legal subset of `status_reason` values is fixed:

| `status` | Legal `status_reason` values |
|---|---|
| `done` | `null` (rubric satisfied or no rubric present), `"user_stopped_at_rubric_gate"` (user accepted partial rubric; PR exists, run ended on user's terms), `"user_stopped_at_no_rubric_gate"` (v14.0.0+; user picked stop at the no-rubric gate), `"no_rubric_in_non_interactive"` (v14.0.0+; non-interactive fallback at no-rubric gate — see Non-interactive fallback policy in `skills/autonomous-loop/SKILL.md` §"No-rubric gate") |
| `paused_max_iterations` | `"max_iterations_reached"` |
| `aborted` | `"user_discarded_at_phase_6"`, `"user_aborted_at_no_go"`, `"user_aborted_at_plan_review_fail"`, `"supervisor_checkpoint"`, `"rubric_dropped_from_brief"`, `"concurrent_session_detected"`, `"invalid_max_iterations"`, **v14.0.0+:** `"non_interactive_without_fallback"`, `"conflicting_mode_flags"`, `"iter_pr_base_mismatch"`, `"rubric_gate_closed_non_interactive"`, `"user_aborted_gh_retry"`, **v14.2.0+:** `"launch_pad_blocked"`, `"user_aborted_at_launch_pad"` |
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
- `ai-agent-manager-plugin/skills/autonomous-loop/SKILL.md` — full protocol; this schema canonicalizes its `DONE — AUTONOMOUS_RUN Summary` section
- `ai-agent-manager-plugin/commands/autonomous.md` — slash command body
- `ai-agent-manager-plugin/docs/FAILURE_ESCALATION.md` — Option C is the loop's failed-iteration re-plan trigger
- `SUPERVISOR_RESULT` schema (above) — each `iterations[].supervisor_status` mirrors `SUPERVISOR_RESULT.status` for that iteration's run

---

## Schema Versioning

All result schemas include a `schema_version` field. This enables forward compatibility:

1. Hooks check `schema_version` before validating fields
2. If `schema_version` is unrecognized, hook warns but does not block
3. New fields can be added without breaking existing validation
4. Breaking changes require incrementing `schema_version`

### Version History

- **POSTMORTEM_RESULT (schema_version 1)** (v14.22.0): New `## POSTMORTEM_RESULT` schema for the read-only `/pr-postmortem` PR review-churn root-cause analyzer. One jq-built JSONL line appended (best-effort, fail-safe, exits 0 on any failure) to `.supervisor/postmortem/results.jsonl` with fields `schema_version`, `ts`, `repo`, `number`, `agent_generated_guess`, `review_rounds`, `additions`, `deletions`, `changed_files`, `categories[]` of `{round, class, self_heal_miss, flow_stage, evidence}`, `self_heal_misses`, `flow_stages{launch_pad, worker, self_heal, unknowable}`, `summary`. Advisory/diagnostic only — never gates, never blocks the PR, write-only trend (never read back), the seed corpus for the deferred synthetic eval harness. No hook validator (the command is the main agent of its own session). Additive — all other schemas unchanged.
- **GROUND_TRUTH_JSON (schema_version 1) + SUPERVISOR_RESULT v1 extension + `session_end` hard-signal fields** (v14.19.0, System Twin M2b slice 1a): New `## GROUND_TRUTH_JSON` schema for the System Twin **ground-truth instrument** emitted by `scripts/run-ground-truth.sh` (resolves project-declared executable acceptance checks from a brief's `## Executable Acceptance` section or `.supervisor/twin/ground-truth.json`, runs each one, emits a single hard PASS/FAIL signal; fields `schema_version`, `ran`, `status: pass|advisory_failures|unverified|skipped`, `checks_total`, `checks_passed`, `pass_rate` "M/N", `per_check[]` of `{kind: cmd|corpus-task|qa-executor, target, status: pass|fail|unverified, reason?}`, `commit`, `date`; ALWAYS exits 0; `qa-executor` kind recognized but DEFERRED to slice 1b). Added the optional additive `ground_truth` object on SUPERVISOR_RESULT (advisory only — NEVER changes `heal_decision` / blocks the PR; follows the `contract_conformance` precedent) and the matching FLAT `session_end` JSONL scalar fields (`ground_truth_status`, `ground_truth_checks_total`, `ground_truth_checks_passed`, `ground_truth_pass_rate`; readers treat absent as `skipped`). The instrument is **distinct from** the eval harness (`EVAL_RESULT` / `run-eval.sh`) and the canary benchmark (`BENCHMARK_JSON` / `run-benchmark.sh`) — "ground-truth" ≠ "eval" ≠ "benchmark". SUPERVISOR_RESULT and GROUND_TRUTH_JSON both stay at `schema_version: 1` — purely additive; the Supervisor SubagentStop hook does not enumerate `ground_truth`, so pre-M2b blocks remain valid. No hook validates GROUND_TRUTH_JSON (standalone script). Slice 1b (QA-Executor dispatch) and the part-2 CI agent loop are deferred.
- **EVAL_RESULT (schema_version 1)** (v14.17.0): New schema for the System Twin **eval instrument** (M2a) emitted by `scripts/run-eval.sh`. Eight fields (`schema_version`, `tasks_total`, `tasks_passed`, `pass_rate`, `per_task[]` of `{id, status: pass|fail}`, `commit`, `date`, `status: ok|unverified`). `pass_rate` (M/N) is the fitness-function signal trackable release-over-release; the determinism invariant covers the tallies/`per_task` only (NOT the contextual `commit`/`date`). `status: unverified` is the fail-safe path (corpus missing or `jq` absent → tasks 0, pass_rate `0/0`, per_task `[]`). The instrument is **distinct from the canary benchmark** (`BENCHMARK_JSON` / `run-benchmark.sh`) and does NOT auto-run the agent loop in CI nor wire ground-truth into Phase 4.5 — both are M2b follow-ups. No SubagentStop hook validates it (the runner is a standalone script). Additive — all other schemas unchanged.
- **REVIEW_HEAL_RESULT (schema_version 1)** (v14.16.0): New schema for the standalone PR review-and-heal loop's outcome block (`/review-pr <pr-url>` + the `ai-agent-manager-plugin:review-pr-runner` agent, and the `/autonomous` EVALUATE Task step). Seven fields (`schema_version`, `decision` enum `PASS | ESCALATED`, `iterations`, `issues_fixed`, `remaining_issues`, `pr_url`, `notified`); canonical names coined in `skills/review-heal/SKILL.md` and consumed verbatim. The loop does NOT redefine review output — each iteration reuses the existing `CODE_REVIEW_RESULT` v3 (`review_mode: diff_review`). No SubagentStop hook validates it (the runner is the main agent of its own fresh session, or runs inline via `/review-pr`; the `/autonomous` path consumes it as a Task step). Additive — all other schemas unchanged.
- **SYSTEM_CONTRACT artifact + SUPERVISOR_RESULT v1 extension + `session_end` hard-signal fields** (System Twin): Added the new `## SYSTEM_CONTRACT` artifact schema (per-subsystem advisory contract under `.supervisor/twin/contracts/`, written solely by `scripts/write-system-contract.sh`, gated on read by `scripts/read-system-contract.sh`), the optional additive `contract_conformance` and `benchmark_result` objects on SUPERVISOR_RESULT, and the matching FLAT `session_end` JSONL scalar fields (`contract_conformance_status`, `contract_violations`, `benchmark_status`, `benchmark_metric`, `benchmark_value`, `benchmark_delta`). These are **additive System Twin fields** — SUPERVISOR_RESULT and SYSTEM_CONTRACT both stay at `schema_version: 1`. The SUPERVISOR_RESULT additions follow the `branch_base` / `pr_state` / `preflight_sync` precedent (optional, advisory-only, not enumerated by the Supervisor SubagentStop hook), so pre-System-Twin blocks remain valid. `contract_conformance` is advisory only and NEVER changes `heal_decision` / blocks the PR. The nested SUPERVISOR_RESULT objects and the flat `session_end` fields are the same hard-signal data in two shapes; `build-insights.sh` reads the flat `session_end` fields.
- **SUPERVISOR_RESULT v1 extension + AUTONOMOUS_RUN status_reason addition** (v14.8.0): Added optional `preflight_sync: enum [clear, overlap_proceed, superseded_proceed, skipped, unverified] | null` to SUPERVISOR_RESULT (records the Phase 1.5 PRE-FLIGHT SYNC gate outcome) and the closed `preflight_overlap_detected` value to the AUTONOMOUS_RUN `status_reason` enum (the gate's CI fail-closed abort, paired with `SUPERVISOR_RESULT.status: failed`). SUPERVISOR_RESULT schema_version stays `1` — `preflight_sync` is optional and additive (same precedent as `branch_base` / `pr_state`); the Supervisor SubagentStop hook does not enumerate it, so pre-v14.8.0 blocks remain valid. AUTONOMOUS_RUN schema_version stays `2` — the new status_reason is an additive enum value, and per the closed-set rule the value was added to both this schema and `skills/autonomous-loop/SKILL.md`.
- **AUTONOMOUS_RUN v2** (v14.0.0): Bumped from v1 → v2. Extended the closed `status_reason` enum with nine new values paired with v14's continuous-mode (multi-iteration default), non-interactive-fallback path, and stacked-branches work: `non_interactive_without_fallback`, `conflicting_mode_flags`, `iter_pr_base_mismatch`, `rubric_gate_closed_non_interactive`, `no_rubric_in_non_interactive`, `user_aborted_gh_retry`, `supervisor_base_branch_mismatch`, `user_stopped_at_no_rubric_gate`, `invalid_max_iterations` (the last was already added in `skills/autonomous-loop/SKILL.md` for v13 but is now first-class in the schema doc). The bump is forward-only — no SubagentStop hook validates AUTONOMOUS_RUN, so schema-1 emissions remain accepted by downstream tooling for the transition window. Tooling SHOULD accept either schema_version and treat unrecognized `status_reason` values as opaque.
- **SUPERVISOR_RESULT v1 extension** (v14.0.0): Added optional `branch_base: string | null` and `pr_state: enum [open, closed_by_loop, close_attempt_failed] | null` fields. Schema_version stays `1` because both additions are optional and purely additive — v13 emissions (which lack both fields) continue to validate against the Supervisor SubagentStop hook (`hooks/hooks.json` matcher `ai-agent-manager-plugin:supervisor-runner`), whose validation prompt enumerates only the v13 field set plus optional `rubric_score`. Purpose: `branch_base` records the declared Base Branch (defaults to `"main"` when absent) for stacked-iteration support; `pr_state` records the post-cleanup PR state for Phase 4.5's base-mismatch path (typically `null` — the cleanup path is rare).
- **SUPERVISOR_RESULT v1 extension** (v12.2.0): Added optional `rubric_score: string | null` field. Format is `"N/M"` where N is a non-negative integer (`>= 0`; `"0/M"` is the legitimate all-fail case where the grader ran but every rubric item failed), M is a positive integer (`>= 1`), and M ≥ N — OR `null`. The two non-null forms are semantically distinct: `null` = grader did not run; `"0/M"` = grader ran and zero items passed. Populated by the Phase 4.5 Haiku grader when the brief contains an `## Outcomes Rubric` section AND `heal_decision == PASS`; `null` otherwise. Schema version was NOT bumped because the addition is optional and additive — pre-v12.2.0 producers and consumers continue to validate without change. The Supervisor SubagentStop hook accepts presence or absence and only validates format when present.
- **AUTONOMOUS_RUN v1** (v13.0.0): New schema for the `/autonomous` orchestration shell's summary block. Autonomous-layer-only — no SubagentStop hook validates it (the autonomous workflow is an inline main-thread chain, not a delegated agent). Status enum (`done | paused_max_iterations | aborted | failed`) is intentionally disjoint from `SUPERVISOR_RESULT.status` to keep the two layers separable. Status-reason enum is closed; new values require updating both this schema and `skills/autonomous-loop/SKILL.md`.
- **WORKER_RESULT v2** (v12.0.0): Added `outputs_verified[]` (itemized presence checks for every output the brief promised) and `outputs_gap` (string; non-empty implies status MUST be `partial`). The SubagentStop hook enforces a cross-field invariant: `outputs_gap` non-empty AND `status: completed` is rejected. v1 emissions remain accepted during the v12.0.0 transition window.
- **EXECUTE_CHECKPOINT v1 extension** (v12.0.0): Added optional fields `adjudication_required: bool`, `missing_outputs: object[]`, and `adjudication_options: string[]`. These fields appear together (all-or-nothing); when `adjudication_required: true`, both arrays MUST be non-empty (hook-enforced). Schema version was NOT bumped because the additions are optional. Same release added a hook rejection of `toolset_gap`-style escalation reasons.
- **CODE_REVIEW_RESULT v2** (v7.0.0): Added `category` field to issues (`new`, `pre_existing`, `nit`). FAIL decisions now require at least one `new` HIGH/BLOCKING issue. Pre-existing issues are reported but do not block.
- **MISSING_FUNCTIONALITY_REPORT v1** (v7.1.0): New schema for QA Executor gap detection output.
- **QA_RESULT + QA_SESSION_PLAN** (v10.3.0): Added optional `app_topology`, `detected_auth_method`, `websocket_detected` (QA_RESULT) and `app_topology`, `auth_method` (QA_SESSION_PLAN). Backward compatible — existing payloads without these fields still validate.
- **QA_RESULT contract fixes** (v10.3.0): `status` enum expanded to include `needs_human` (matches executor/blueprint usage). `bugs_found` reclassified as integer count (was object[]); detailed bug records now live in new optional `bugs` field. `bugs_blocking` integer added. Added missing fields to formalize executor emissions: `tests_run_this_session`, `depth`, `environment`, `discovery_warnings`, `coverage`, `coverage_weighted`, `risk_score`, `interaction_coverage`, `discovery_gaps`, `environment_issues`, `notes`. Resolves prior doc/contract drift.
- **MISSING_FUNCTIONALITY_REPORT** (v10.3.0): `gaps` may be `[]` when analysis finds nothing. Emission is always required — absent block means Phase 4.5 was skipped.
- **GRAPHQL_RISK_OVERRIDES** (v10.3.0): New output contract emitted by QA Strategist in Strategy Mode when `api_style` is `graphql` or `mixed`.
- All other schemas remain at v1.

---

## MISSING_FUNCTIONALITY_REPORT

Produced by QA Executor during Phase 4.5 gap analysis. Separate from QA_RESULT.

```yaml
MISSING_FUNCTIONALITY_REPORT:
  schema_version: 1                    # integer, required — always 1
  task_id: string                      # required — QA run identifier
  gaps: object[]                       # required — MAY be empty. An empty array with total_gaps: 0 is valid and means "analysis ran, no gaps found"
    - category: enum [missing_crud, missing_pagination, missing_search,
                      missing_validation, missing_error_handling, missing_confirmation,
                      missing_loading_state, missing_rate_limiting,
                      data_integrity_risk, security_boundary_gap, best_practice_gap]
      severity: enum [CRITICAL, HIGH, MEDIUM, LOW]
      location: string                 # route/endpoint/component where gap found
      description: string              # what's missing and why it matters
      evidence: string                 # what discovery data led to this conclusion
      recommendation: string           # what should be built/fixed
  summary: string                      # required — concise summary of all gaps
  total_gaps: integer                  # required — total gap count
  critical_count: integer              # required — CRITICAL gaps count
```

**Validation rules:**
- **Always emit the report** — even when `gaps` is empty. Absence of the block means Phase 4.5 was skipped (Strategist will reject).
- `gaps` MAY be `[]` (empty). When empty, `total_gaps` MUST be `0` and `critical_count` MUST be `0`.
- Each gap (when present) must have `category`, `severity`, `location`, `description`
- `total_gaps` must equal `gaps.length`
- `critical_count` must equal count of gaps with `severity=CRITICAL`
- `summary` must be present (e.g., "No gaps detected." for empty report)

**Example:**
```
MISSING_FUNCTIONALITY_REPORT:
  schema_version: 1
  task_id: qa-run-2026-03-22
  gaps:
    - category: missing_crud
      severity: HIGH
      location: POST /api/tournaments
      description: Tournament entity has create endpoint but no edit (PUT) or delete (DELETE)
      evidence: Discovery found POST /api/tournaments but no PUT or DELETE for same resource
      recommendation: Add PUT /api/tournaments/:id and DELETE /api/tournaments/:id endpoints
    - category: missing_rate_limiting
      severity: HIGH
      location: POST /api/auth/login
      description: Login endpoint has no rate limiting — brute force attack vector
      evidence: 5 rapid requests all returned 200 with no 429 response
      recommendation: Add rate limiting (max 5 attempts per minute per IP)
    - category: missing_pagination
      severity: MEDIUM
      location: GET /api/tournaments
      description: List endpoint returns all items with no pagination support
      evidence: No limit/offset/page query parameters detected in API calls
      recommendation: Add pagination with limit/offset or cursor-based approach
  summary: 3 gaps found (2 HIGH, 1 MEDIUM). Missing CRUD operations and rate limiting are highest priority.
  total_gaps: 3
  critical_count: 0
```

---

## GRAPHQL_RISK_OVERRIDES

Produced by QA Strategist in Strategy Mode **only when `api_style` is `graphql` or `mixed`**.
Consumed by QA Executor in Phase 7 write-back to persist per-operation risk into `discovery/api-calls.json`.

This is a markdown-table contract (not YAML) because it appears inline in the Strategist's textual output. The Executor parses it by header row match.

### Format

```markdown
### GraphQL Risk Overrides

| Operation | Method | Risk | Reason |
|---|---|---|---|
| createUser | MUTATION | HIGH | auth + data mutation |
| getUsers | QUERY | MEDIUM | (default) |
| deleteOrg | MUTATION | HIGH | destructive, admin-only |
| healthCheck | QUERY | LOW | no side effects |
```

### Validation Rules

- Heading must contain the literal text `GraphQL Risk Overrides` (case-insensitive)
- Table columns MUST be `Operation | Method | Risk | Reason` in this order
- Match key into `api-calls.json` is `Operation` + `Method` together (a query and mutation can share the same name — method disambiguates)
- `Method` values: `QUERY` | `MUTATION` (uppercase)
- `Risk` values: `HIGH` | `MEDIUM` | `LOW`
- `Reason` is free-form human-readable text (not parsed by machines)
- Block is **omitted entirely** when `api_style` is not `graphql`/`mixed` — absence is not an error
- If block is absent for a graphql app: Phase 5B default risks stand (no write-back performed)

### Write-back Behavior (Executor)

For each row in the table:
1. Match by `Operation` + `Method` against entries in `discovery/api-calls.json`
2. If row's `Risk` differs from entry's current `risk`: update the entry's `risk` field via Edit
3. If row has no matching entry: log warning, skip (Strategist may have hallucinated an operation)
4. Operations in `api-calls.json` not listed in the override table: keep existing Phase 5B default

Executor updates `api-calls.json` in-place; no separate overrides file is persisted.

---

## LAUNCH_PAD_RESULT

Produced by Launch Pad at the end of its workflow (after Phase 6 SAVE) to communicate the outcome and — critically — the **exact path of the saved Supervisor-Ready Brief** for programmatic consumers (notably `/autonomous` PLAN phase, which previously relied on a fragile `ls`-diff of `.supervisor/jobs/pending/`).

**Added in v14.2.0.** Emission is non-blocking — the schema is purely additive. Existing Launch Pad consumers (the user reading the markdown output) are unaffected; new consumers (`/autonomous`) read the structured block from the transcript, or from the SubagentStop hook payload when Launch Pad runs in `-runner` mode (`claude --agent ai-agent-manager-plugin:launch-pad-runner`).

```yaml
LAUNCH_PAD_RESULT:
  schema_version: 1                    # integer, required — always 1
  status: enum [saved, discarded, blocked, aborted]  # required
  saved_brief_path: string | null      # required field; null unless status=saved
  summary: string                      # required — one-line outcome (≤ 200 chars recommended)
```

**Validation rules (schema_version: 1):**
- `schema_version` must equal `1`.
- `status` must be one of: `saved` | `discarded` | `blocked` | `aborted`.
- `saved_brief_path`:
  - When `status: saved` → MUST be a non-empty string matching `.supervisor/jobs/pending/*.md`, and the file MUST exist on disk at emission time.
  - When `status ∈ {discarded, blocked, aborted}` → MUST be the literal YAML `null` (not the string `"null"`, not empty).
- `summary` must be a non-empty string.

**Status semantics:** `saved` (Phase 6 save completed, file on disk) · `discarded` (user chose Discard, no file) · `blocked` (Phase 1 BLOCKER or Plan Review FAIL × 3 without override; save never offered) · `aborted` (user aborted mid-flight; no clean Phase 6 outcome).

**Emission cadence:** emitted **once per Launch Pad invocation**, immediately after Phase 6 (whether or not a file was written). The SubagentStop hook (`scripts/validate-launch-pad-result.py`) validates the block in the agent-owned (`-runner`) path; for the inline slash-command path the autonomous-loop skill reads the last emitted block from the transcript and runs the same validator in `--raw` mode, mirroring the `SUPERVISOR_RESULT` pattern.

**Example (status: saved):**
```yaml
LAUNCH_PAD_RESULT:
  schema_version: 1
  status: saved
  saved_brief_path: .supervisor/jobs/pending/2026-05-28-add-version-command.md
  summary: Plan Review PASS on attempt 1/3; saved Supervisor-Ready Brief for /supervisor handoff.
```

**Example (status: discarded):**
```yaml
LAUNCH_PAD_RESULT:
  schema_version: 1
  status: discarded
  saved_brief_path: null
  summary: User chose Discard at Phase 6 after reviewing the assembled brief.
```

**Consumer pattern (`/autonomous` PLAN phase):** when `status: saved`, read `LAUNCH_PAD_RESULT.saved_brief_path` directly as the iteration's `current_brief_path`. When `status ∈ {discarded, blocked, aborted}`, exit the loop with the corresponding terminal status. The `ls`-diff fallback (Launch Pad pre-v14.2.0) remains supported during the transition window but is no longer primary.

---

## REVIEW_HEAL_RESULT

Produced by the standalone PR **review-and-heal** loop — emitted once at the end of the bounded review→fix→re-review cycle. The loop is the conceptual extraction of Supervisor **Phase 4.5** into a fresh, PR-URL-keyed session (no Supervisor job, no `.supervisor/state.md`, no worktree fan-out). Its canonical names and field list are coined in `skills/review-heal/SKILL.md` (the single source of truth) and consumed verbatim here.

**Added in v14.16.0.** The block reports the *outcome of the loop*; it does **not** redefine review output. Each review iteration reuses the existing **`CODE_REVIEW_RESULT` schema (v3, `review_mode: diff_review`)** verbatim — the review-and-heal loop consumes `CODE_REVIEW_RESULT` and never re-coins it.

**Emission contexts (two senses of "fresh"):**
- **`/review-pr` runner** — `ai-agent-manager-plugin:review-pr-runner`, running as the main agent of its own fresh OS process (launched by `dispatch-pr-review.sh` from the plain-`/supervisor` completion tail) or inline on the main thread via `/review-pr <pr-url>`. Emits one `REVIEW_HEAL_RESULT` at exit.
- **`/autonomous` EVALUATE Task step** — the review-heal loop body runs as a Task-spawned step with fresh isolated context (NOT a nested `claude` process and NOT a `Task` on the `-runner` agent). The EVALUATE step parses the emitted `REVIEW_HEAL_RESULT` to decide its next action.

```yaml
REVIEW_HEAL_RESULT:
  schema_version: 1                    # integer, required — always 1
  decision: enum [PASS, ESCALATED]     # required — exactly these two values (no FAIL in the result block)
  iterations: int                      # required — how many review→fix→re-review cycles ran
  issues_fixed: int                    # required — count of new+BLOCKING/HIGH issues addressed by fix workers
  remaining_issues: int                # required — new+BLOCKING/HIGH issues still open at exit
  pr_url: string                       # required — the PR this run operated on
  notified: bool                       # required — true if a NEEDS_HUMAN/escalation notification was attempted
```

**Field notes:**

| Field | Type | Notes |
|---|---|---|
| `schema_version` | int | Always `1`. |
| `decision` | enum | Exactly `PASS` or `ESCALATED`. There is **no `FAIL`** in the result block: a reviewer `FAIL` is an internal loop signal that drives a fix iteration, becoming terminal only as `ESCALATED` (loop exhausts or reviewer escalates with `NEEDS_HUMAN`). |
| `iterations` | int | Number of review→fix→re-review cycles run. Bounded — **default 3** (the `--heal-iterations` analogue). |
| `issues_fixed` | int | Count of `new` + BLOCKING/HIGH findings addressed by `general-purpose` fix workers across all iterations. |
| `remaining_issues` | int | `new` + BLOCKING/HIGH findings still open at loop exit. `0` on `PASS`; the escalated count on `ESCALATED`. |
| `pr_url` | string | The PR URL the run operated on (the loop's single input; resolved to a head branch via `gh pr view <pr-url> --json headRefName`). |
| `notified` | bool | `true` whenever a NEEDS_HUMAN/escalation notification was *attempted* (desktop banner + webhook are best-effort, fire-and-forget, always exit 0 — delivery is unobservable from the loop, so this records attempt, not success). |

**Outcome model:**
- `PASS` → clean diff; loop done; `remaining_issues: 0`. The loop **NEVER merges the PR** (no-self-trust: an automated reviewer that also merges removes the human gate). PR is left open for a human to merge.
- `ESCALATED` → reviewer escalated (`NEEDS_HUMAN`) **or** the loop exhausted its iteration bound with issues remaining. Findings are posted to the PR via `gh pr comment`, notifications fired best-effort, PR left open. Never auto-fixes past escalation, never merges.

**No re-coining:** the seven fields and the `decision` enum match `skills/review-heal/SKILL.md` exactly. Do NOT rename or add fields here without updating that skill first (it is authoritative).

---

## Validation Location

Schema validation occurs in the **hook execution layer**:
- Per-agent `SubagentStop` hooks (in agent frontmatter) validate Worker and Execute Manager results
- Cross-cutting `SubagentStop` hooks (in `hooks.json`) validate Code Reviewer and QA Executor results
- Validation is never duplicated in Supervisor or plugin runtime
