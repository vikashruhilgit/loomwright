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
  heal_remaining_issues: integer       # required — count of new+BLOCKING/HIGH issues still unresolved in final review; 0 when heal_loop_ran=false or heal_decision=PASS; may be 0 with heal_decision=ESCALATED only when error is non-empty (thrash escalation)
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
  knowledge_sources_used: string[]     # optional (v14.28.0+) — advisory, non-gating telemetry: which memory sources the run actually consulted (lessons / project memory / per-agent memory / twin / brain-context). Self-reported — records *claimed* usage, not machine-verified reads. Open-set lowercase source tags: `project_memory`, `lessons:<category>`, `agent_memory:<agent>`, `twin:<path>`, `brain_context`. Absent ⇒ "none used". NEVER gates / changes `heal_decision` / blocks the PR; NOT enumerated by the Supervisor SubagentStop hook. Same data appears as a FLAT array on the `session_end` JSONL line — the dual-shape precedent `contract_conformance` uses. (As of v14.33.0 `build-insights.sh` / `/insights` aggregates and surfaces this field in the `## Knowledge sources (memory APPLY)` dashboard section — runs-reporting-a-source count, top source tags, per-version usage.) `brain_context` stays in the open-set vocabulary (past emissions remain valid) but has no live plugin-side emitter since the graphify-tier retirement (2026-08-17). Schema_version stays 1 — field is additive and optional.
  until_mergeable_dispatched: bool | null  # optional (v14.32.0+) — observability: `true` when a per-PR dispatch marker exists for this PR under `.supervisor/review-dispatch/`, i.e. the `--until-mergeable` drain was dispatched by EITHER the Supervisor completion tail / Phase 4.5 step 5.5 OR the `PostToolUse[Bash]` hook backstop (`hook-dispatch-on-pr-create.sh`, which fires at `gh pr create`). **Reconciled against the marker, NOT keyed on whether the Supervisor's own step 5.5 ran** — on the inline path that step is often skipped while the hook still dispatches, so keying on the agent's own action records a false negative (v14.39.0 fix). The dispatch is **ON by default** after a PASS/normal completion that produced a PR (AC7), so `true` is the common case. `false`/`null`/absent ⇒ NOT dispatched (no marker) — i.e. the until-mergeable signal was opted out (`--no-until-mergeable` / `.auto_until_mergeable == false`), the whole post-completion drain was suppressed (`--no-auto-review` / `.auto_review == false`), or no PR was produced. Records the dispatch DECISION, not the drain's outcome — the drain's `REVIEW_HEAL_RESULT` is the authority for readiness (see `skills/review-heal/SKILL.md`). NEVER gates / changes `heal_decision` / blocks the PR. Schema_version stays 1 — field is additive and optional.
  until_mergeable_log: string | null   # optional (v14.32.0+) — observability: path to the dispatched drain's run log (e.g. `.supervisor/logs/review-pr-dispatch-<...>.log`) when `until_mergeable_dispatched` is true; `null`/absent otherwise. Informational only. Schema_version stays 1 — field is additive and optional.
  risk_classification:                 # optional (v15.72.0+) — ADVISORY record of `scripts/classify-risk.sh "$BASE_BRANCH" HEAD` run unconditionally at Phase 4.5 entry to the red-team lens (decision D1); ABSENT on the Phase 4.5 bypass paths (`--skip-self-heal`, resume-thrash, base-mismatch cleanup) — absent ⇒ valid. NEVER changes heal_decision, NEVER blocks the PR; the `/automate` gate does NOT read it (it re-classifies the SHA it judges — §AUTOMATE_RUN / `skills/automate-loop/SKILL.md` §10 cond 6). Schema_version stays 1 — additive and optional.
    high_risk: boolean | null          # null = unclassifiable (bad ref / not a git repo / git or jq failure) — the lens treats null as "spawn the advisory pass"
    reasons: string[]                  # the script's `reasons` (`path:` / `content:` / `size:` / `project:` prefixed; `unclassifiable: <reason>` when high_risk is null); [] when false
  heal_dismissed: [{finding: string, reason: string, source: string, severity?: string}]   # optional (dismissed-findings-01) — the self-heal-side PARALLEL to REVIEW_HEAL_RESULT.dismissed (docs/RESULT_SCHEMAS.md §REVIEW_HEAL_RESULT): findings the Phase 4.5 review-and-fix loop saw but did NOT dispatch to a fixer. "Empty ⇒ absent" — OMITTED when zero findings were dismissed this run (never `heal_dismissed: []`). `reason` is a CLOSED enum here (unlike the drain-side free-text `dismissed.reason`): `pre_existing | nit | drift | below_severity_floor` — the four ways a review.issues entry can be excluded from `fixable_issues` (category != new+BLOCKING/HIGH). `source` is `code_reviewer | red_team | voter:<provider>` — the Phase 4.5 lenses (distinct from the drain's channel-name enum). `severity` is OPTIONAL (the dismissed `CODE_REVIEW_RESULT` issue's own severity, so in practice only `BLOCKING | HIGH | MEDIUM | LOW` — that enum has no `INFO`; the shared `BLOCKING | HIGH | MEDIUM | LOW | INFO` set accepts `INFO` only because a drain main-pass `dismissed` item can carry it; absent ⇒ unspecified — automate-followups/12). NEVER changes heal_decision, NEVER blocks the PR — purely a report of what was seen and knowingly left alone. Schema_version stays 1 — additive and optional.
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
- when `heal_decision=ESCALATED`: `heal_remaining_issues>=1` OR `error` non-empty (the resume-thrash escalation path legitimately reports 0 known remaining issues with `error: "self_heal_resume_thrash"`)
- `summary` must be present
- `rubric_score` is optional (additive in v12.2.0, schema version unchanged at 1). When present, it MUST be either `null` or a string matching the format `"N/M"` where N is a non-negative integer (`>= 0` — `"0/M"` is the legitimate all-fail case where the grader ran but every rubric item failed), M is a positive integer (`>= 1` — there is no zero-item rubric), and M ≥ N. The two non-null forms have distinct meaning: `null` = grader did not run (no rubric in brief, `heal_decision != PASS`, or grader parse failure); `"0/M"` = grader ran and scored zero items. When absent, validators MUST treat it as `null`. The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `rubric_score`.
- `branch_base` is optional (additive in v14.0.0, schema version unchanged at 1). When present, it MUST be either `null` or a non-empty string naming the declared Base Branch (e.g., `"main"`, `"feature/parent-iter"`). Absent OR `null` means the run targeted `"main"` by default. The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `branch_base` — v13 blocks without this field remain valid. Consumers reading the field MUST handle `null`/absent as equivalent to `"main"`.
- `pr_state` is optional (additive in v14.0.0, schema version unchanged at 1). When present, it MUST be either `null` or one of `"open"`, `"closed_by_loop"`, `"close_attempt_failed"`. Absent OR `null` is the normal case (Phase 4.5 base-mismatch cleanup did not execute). The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `pr_state` — v13 blocks without this field remain valid.
- `preflight_sync` is optional (additive in v14.8.0, schema version unchanged at 1). When present, it MUST be either `null` or one of `"clear"`, `"overlap_proceed"`, `"superseded_proceed"`, `"skipped"`, `"unverified"`. Absent OR `null` means EITHER the Phase 1.5 PRE-FLIGHT SYNC gate did not run (legacy emission, or a pre-v14.8.0 `--continue` resume that lands after the gate) OR the run exited before recording a *proceed* classification — the `revise-scope` checkpoint path (`status: checkpoint`) and the fail-closed abort path (`status: failed` + `error: "preflight_overlap_detected"`) both leave `preflight_sync` null and carry the classification elsewhere (Decisions Log entry / `error`). The Supervisor SubagentStop hook MUST NOT reject a SUPERVISOR_RESULT solely for the presence or absence of `preflight_sync` — pre-v14.8.0 blocks without this field remain valid (the hook does not enumerate it, mirroring the `branch_base` / `pr_state` additive precedent). Neither the `revise-scope` nor the fail-closed abort path uses a `preflight_sync` enum value; disambiguate via `status` + `error` (the abort emits `error: "preflight_overlap_detected"` — see the `preflight_overlap_detected` AUTONOMOUS_RUN `status_reason` below).
- `error: "resume_state_invalid"` (additive in v15.3.0, schema version unchanged at 1) — a closed `error` value emitted with `status: failed` when the `/supervisor --continue` **resume validation gate** refuses a loaded state file (scratchpad or `.supervisor/state.md`) that fails the fail-closed parse contract: missing `## Session` block, `phase`/`status` outside the closed enums, or an asserted `branch:` that does not `git rev-parse --verify`. Authoritative contract: `skills/state-management/SKILL.md` §"Resume validation gate"; gate location: the Phase 0 INIT resume-state check in `skills/supervisor-config/SKILL.md` (the Supervisor's Phase 0 protocol authority; Phase 1 ACQUIRE's resume read references the same gate). The run refuses BEFORE consuming any state — it never silently falls back to a fresh start, and there is no escape-hatch flag (deleting the bad state file is the escape hatch). No hook change: the Supervisor SubagentStop hook already accepts any non-empty `error` when `status=failed` and does not enumerate error strings. **Deliberately NOT added to AUTONOMOUS_RUN's `failed` `status_reason` set:** the autonomous loop never invokes `/supervisor --continue` (the loop has no resume contract in v1 — `"supervisor_checkpoint"` is terminal there), so this error cannot surface through it; if a supervisor `failed` result carrying it ever reached the loop anyway, `"supervisor_failed_other"` case (a) is the catch-all.
- `error: "children_unsettled: {unsettled_agent_ids}"` (additive in v15.80.0, schema version unchanged at 1) — emitted with `status: failed` when Phase 4 FINALIZE's pre-merge safety-gate Point 5 (`skills/async-orchestration/SKILL.md` §"Phase 4 FINALIZE procedure" step 1) finds at least one `agent_identity` row in this session's JSONL log with no matching terminal lifecycle row (`subtask_complete` / `token_ledger` / `agent_lifecycle: failed` / `agent_lifecycle: ended`), under `--non-interactive` / CI / stdin-not-a-TTY and without `--skip-children-check`. Interactively the same condition is a soft gate (`AskUserQuestion`: proceed anyway / investigate / abort), never an automatic `failed`. See `## Completion authority join` above for the full join and `docs/FAILURE_ESCALATION.md` §"Supervisor Failure" for the escalation shape. **Deliberately NOT added to AUTONOMOUS_RUN's `failed` `status_reason` set in this change** — out of scope for `.supervisor/requirements/orca-derived/02-completion-authority.md`, which specifies only the FINALIZE gate and `SUPERVISOR_RESULT.error`; a supervisor `failed` result carrying it that reaches the autonomous loop anyway falls into the `"supervisor_failed_other"` catch-all, same as any other unenumerated error.
- **finalize-gate marker** (automate-followups/33, additive, schema version unchanged): `.supervisor/logs/{session_id}.finalize-gate` (plugin session id) holds `{"children_check":"settled"|"skipped","children_status":"<check-children-settled.sh status>","head_sha":"<sha>","ts":"<utc>"}`. Written ONLY by `scripts/guard-finalize-publish.sh write-marker [--skip-children-check]`, which runs Point 5's `--all` check itself (`settled` / `no_identity_rows` ⇒ `children_check: settled`; the flag ⇒ `skipped`; anything else ⇒ no marker, stale one removed). Read by the same script's fail-CLOSED `PreToolUse[Bash]` mode, which denies `git push` / `gh pr create` in a live Supervisor run until the marker's `head_sha` equals HEAD. Not a `SUPERVISOR_RESULT` field — the result's existing `children_check` value is unchanged; the marker is the mechanism that makes Point 5 run before anything is published.
- `knowledge_sources_used` is optional (additive in v14.28.0, schema version unchanged at 1). When present it MUST be an array of short lowercase source-tag strings drawn from the open set `project_memory`, `lessons:<category>`, `agent_memory:<agent>`, `twin:<path>`, `brain_context`. Absent (the common case) means "no memory sources were consulted, or the run did not report them" — readers treat absent as "none used". The field is **advisory and non-gating**: it NEVER changes `heal_decision`, NEVER blocks the PR, and is NOT enumerated by the Supervisor SubagentStop hook, so blocks with or without it validate unchanged (mirroring the `branch_base` / `pr_state` / `preflight_sync` additive precedent). Pre-v14.28.0 blocks without this field remain valid. The same data is also emitted as a FLAT array on the `session_end` JSONL line (see the `session_end` hard-signal fields section) — two shapes of the same data, the dual-shape precedent `contract_conformance` already uses. **(v14.46.0)** The Phase 4.5 findings→community **bridge** read (`read-bridge.sh`, the graph-community companion to the exact-path churn ledger) counts under the EXISTING `brain_context` tag when its consult returns a hit — the bridge IS a brain-context read path, so it does NOT introduce a new source tag and does NOT bump `schema_version`. **(Retired 2026-08-17 — graphify-tier retirement.)** The v14.46.0 note is kept as historical record but is **no longer live**: `read-bridge.sh` and the bridge consult were removed with the tier. `brain_context` itself **stays in the open-set vocabulary** (open set, no schema change; past emissions remain valid) but has **no live plugin-side emitter** as of this change.
- `until_mergeable_dispatched` and `until_mergeable_log` are optional (additive in v14.32.0, schema version unchanged at 1). When present, `until_mergeable_dispatched` MUST be `true`, `false`, or `null`; `until_mergeable_log` MUST be a non-empty string path or `null`. Absent OR `null`/`false` means no per-PR dispatch marker was found — i.e. the `--until-mergeable` drain was opted out (`--no-until-mergeable` / `.auto_until_mergeable == false`), the whole drain suppressed (`--no-auto-review` / `.auto_review == false`), no PR was produced, or the dispatcher no-oped before writing a marker. (The dispatch is ON by default after PR creation — AC7.) Both are **advisory and non-gating**: they record the marker-reconciled dispatch DECISION for observability and NEVER change `heal_decision`, NEVER block the PR, and are NOT enumerated by the Supervisor SubagentStop hook, so blocks with or without them validate unchanged (mirroring the `branch_base` / `pr_state` / `preflight_sync` / `knowledge_sources_used` additive precedent). Pre-v14.32.0 blocks without these fields remain valid. The drain's own `REVIEW_HEAL_RESULT` (schema v2) remains the authority for the drain's readiness outcome — these two SUPERVISOR_RESULT fields only record that a dispatch marker exists for this PR and where its log lives.
- `risk_classification` is optional (additive in v15.72.0, schema version unchanged at 1). When present it MUST be an object whose `high_risk` is `true`, `false`, or `null` and whose `reasons` is an array of strings. Absent (every Phase 4.5 bypass path, and every pre-v15.72.0 emission) is valid and carries no meaning beyond "the lens did not run" — mirroring `red_team_advisory: disabled`. The value is **advisory and non-gating**: it NEVER changes `heal_decision`, NEVER blocks the PR, and is NOT enumerated by the Supervisor SubagentStop hook (`validate-supervisor-result.py` accepts blocks with or without it — `test-classify-risk.sh` pipes one through). It records what `scripts/classify-risk.sh` said about `$BASE_BRANCH...HEAD` at Phase 4.5 time; the `/automate` trusted-merge gate (`skills/automate-loop/SKILL.md` §10 condition 6) does NOT consume this field — as of red-team-hardening item 03 (v15.88.0), `gate_eval` re-classifies the SHA it is judging itself, at gate time, with no `ctx.json` input for this field (`automate-helpers.sh gate_eval` cond 6) — a caller cannot hand the gate this value at all. The heuristic is defined ONCE, in the script's data lists; `classify-risk.sh --kind-table` prints it and this is its ONE committed copy (the `test-classify-risk.sh` suite fails if it drifts). Projects may only ADD surfaces via a committed `.agent/risk.json` (`{"schema_version":1,"paths":[..],"content":[..]}`) — there is no `exclude` key, no flag and no config key that lowers a classification (owner decision R5):

<!-- risk-table:begin -->
| Branch | Rule | Scope | Reason prefix |
|--------|------|-------|---------------|
| (a) security / financial / migration | `*auth*`, `*authz*`, `*security*`, `*crypto*`, `*secret*`, `*token*`, `*payment*`, `migrations/`, `*migration*` | changed path OR changed line, case-insensitive substring | `path:` / `content:` |
| (b) workflow / orchestration surfaces | `.github/workflows/`, `hooks/`, `agents/`, `commands/`, `skills/` | changed path under that directory (at the root or anywhere below) | `path:` |
| (b) workflow / orchestration words | `workflow`, `automation`, `orchestration` | changed path OR changed line, case-insensitive substring | `path:` / `content:` |
| (c) size | `changed_lines > 400` | added+removed lines of `git diff <base>...<head>` (`+++`/`---` headers excluded) | `size:` |
| (c) size | `changed_files > 15` | line count of `git diff <base>...<head> --name-only` | `size:` |
| project (add-only) | `.agent/risk.json` `paths[]` (`case` globs — `*`/`**` match across `/`) and `content[]` (literal words, case-insensitive) | changed path / changed line; NO `exclude` key (R5) | `project:` |
<!-- risk-table:end -->
- **Multi-voter heal counters (additive in v15.8.0 — prose inside `summary`, NOT a schema field):** when the run had multi-voter Phase 4.5 verification enabled (`--multi-voter-heal` / `.multi_voter_heal` — authority: `skills/self-heal-advisory/SKILL.md` Part 2 §"Multi-voter verification"), the required `summary` string additionally carries the per-run counters `findings_raised` / `findings_refuted` / `findings_fixed` as additive prose (e.g. `multi_voter: findings_raised=3 findings_refuted=1 findings_fixed=2`). This follows the `red_team_advisory`-in-summary precedent from that same skill: no new field is added, the Supervisor SubagentStop hook does not parse the counters, and `schema_version` stays `1`. Blocks without the counters (multi-voter OFF — the default) remain valid unchanged.
- `heal_dismissed` is optional (additive, dismissed-findings-01, schema version unchanged at 1). When present it MUST be an array of `{finding: string, reason: string, source: string}` objects; `reason` MUST be one of the closed enum `pre_existing | nit | drift | below_severity_floor` (mirroring `CODE_REVIEW_RESULT`'s `category` enum plus the fix-time severity-floor exclusion — see `` docs/result-schemas/code-review-result.md:29 [pins: `category: enum [new, pre_existing, nit, drift]`] `` for the 4th `category: drift` value); `source` MUST be one of `code_reviewer | red_team | voter:<provider>`; `severity` is OPTIONAL (additive, automate-followups/12, no schema_version bump) — when present one of `BLOCKING | HIGH | MEDIUM | LOW | INFO`, but because it is the dismissed issue's own `CODE_REVIEW_RESULT` severity (a closed `BLOCKING | HIGH | MEDIUM | LOW` enum) a Phase 4.5 item never carries `INFO` — `INFO` is reachable only via the drain main-pass `REVIEW_HEAL_RESULT.dismissed` path; absent ⇒ unspecified (every pre-automate-followups/12 emission). `/automate`'s dismissed-findings decision step thresholds on it (`skills/automate-loop/SKILL.md` §6 "Dismissed-findings decision step (before the park)"). **"Empty ⇒ absent"**: a run with zero dismissed findings OMITS the key entirely — never `heal_dismissed: []`. Absent is the common case (every Phase 4.5 run whose review pass found nothing to dismiss, and every pre-dismissed-findings-01 emission). The value is **advisory and non-gating**: it NEVER changes `heal_decision`, NEVER blocks the PR, and is NOT enumerated by the Supervisor SubagentStop hook, so blocks with or without it validate unchanged (mirroring the `branch_base` / `pr_state` / `preflight_sync` / `risk_classification` additive precedent). This field is the self-heal-side PARALLEL to `REVIEW_HEAL_RESULT.dismissed` above — the two `source` enums are DIFFERENT (drain channel names vs. Phase 4.5 lens names) because the two loops read from different origins; do not conflate them. Authority for the emission logic: `skills/self-heal-advisory/SKILL.md` Part 2 (the `fixable_issues` filter and its `heal_dismissed` accumulator).

**v14.0.0 additive fields (backwards-compat):** `branch_base` and `pr_state` are purely additive optional fields. The Supervisor SubagentStop hook (see `hooks/hooks.json` matcher `loomwright:supervisor-runner`) validates the v13 field set plus optional `rubric_score`; it does NOT enumerate `branch_base` / `pr_state` and therefore accepts blocks with or without them. Existing v13 SUPERVISOR_RESULT emissions (which lack both fields) continue to validate against the hook unchanged. Schema_version remains `1` precisely because the additions are optional and additive.

**v14.8.0 additive field (backwards-compat):** `preflight_sync` is a purely additive optional field following the same precedent. The Supervisor SubagentStop hook does NOT enumerate it, so blocks with or without it validate unchanged, and pre-v14.8.0 consumers ignore it (no validation failure). Schema_version remains `1`.

**v14.32.0 additive fields (backwards-compat):** `until_mergeable_dispatched` and `until_mergeable_log` are purely additive optional observability fields following the same precedent. They record whether a per-PR dispatch marker exists for the (default-ON, AC7) `--until-mergeable` review-and-heal drain (and where its log lives), regardless of whether the marker was written by the completion tail or the hook backstop — advisory only, never gating. The Supervisor SubagentStop hook does NOT enumerate them, so blocks with or without them validate unchanged, and pre-v14.32.0 consumers ignore them. Schema_version remains `1`.

**System Twin additive fields (backwards-compat):** `contract_conformance`, `benchmark_result`, and `ground_truth` are purely additive optional objects following the same `branch_base` / `pr_state` / `preflight_sync` precedent. All are **advisory only** — `contract_conformance` NEVER changes `heal_decision` and NEVER blocks the PR (its `findings[].severity` is `info` or `advisory` by construction, never `blocking`/`high`); `benchmark_result` is informational; `ground_truth` (added v14.19.0, M2b slice 1a) NEVER changes `heal_decision` and NEVER blocks the PR (its `findings[].severity` is `info` or `advisory` by construction, never `blocking`/`high`). The Supervisor SubagentStop hook does NOT enumerate any of these fields, so blocks with or without them validate unchanged, and pre-System-Twin consumers ignore them. Schema_version remains `1`. Field semantics:
- `contract_conformance.checked` is `false` (with `status: skipped` or `unverified`) when no contracts exist in `.supervisor/twin/` or the conformance tooling is unavailable. Use `unverified`, not `skipped`, whenever a contract that EXISTS was withheld by the read gate — that is a missing capability, not nothing to do. Two triggers, and the second is the commoner one: the whole-store read reports `twin_store_status: dark` (every stored contract failed provenance), OR a `--subsystem` read for a touched id reports `dark` while the store overall is only `degraded` (that one id has a stored contract the gate withheld). A `--subsystem` read for an id with no stored contract reports `empty`, never `dark`, so the second trigger cannot fire on a subsystem that simply has no contract; `status: pass` requires `violations: 0`; `status: advisory_violations` requires `violations >= 1` and a non-empty `findings[]`. Field names are a contract with the System Twin builder (ST3 writes, ST4 reads) — do not rename.
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

