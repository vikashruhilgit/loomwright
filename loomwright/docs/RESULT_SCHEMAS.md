# Result Schemas

> Strict contracts for all agent result blocks. Hooks validate against these schemas.
> All schemas include a `schema_version` field for forward compatibility. Current versions: CODE_REVIEW_RESULT at `schema_version: 3` (review modes + consistency audit; v2 accepted for legacy); WORKER_RESULT at `schema_version: 2` (outputs_verified contract; v1 accepted for the v12.0.0 transition window); AUTONOMOUS_RUN at `schema_version: 2` (v14.0.0 status_reason extension; v1 accepted, no hook validation); LAUNCH_PAD_RESULT at `schema_version: 1` (added v14.2.0, validated by `scripts/validate-launch-pad-result.py`); REVIEW_HEAL_RESULT at `schema_version: 2` (v14.30.0 — `--until-mergeable` drain mode adds the `READY` decision + drain/postmortem fields; v1 still accepted for legacy artifacts / the default diff-only loop; added v14.16.0, no hook validator — runner is the main agent of its own session); EVAL_RESULT at `schema_version: 1` (added v14.17.0, the System Twin eval instrument emitted by `scripts/run-eval.sh`, no hook validator — standalone script); GROUND_TRUTH_JSON at `schema_version: 1` (added v14.19.0, the System Twin ground-truth instrument emitted by `scripts/run-ground-truth.sh`, no hook validator — standalone script; consumed advisory-only by Supervisor Phase 4.5); POSTMORTEM_RESULT at `schema_version: 1` (added v14.22.0, the advisory PR review-churn trend line appended by `/pr-postmortem` to `.supervisor/postmortem/results.jsonl`, no hook validator); GATE_VERDICT at `schema_version: 1` (Strategist↔Executor gate-audit handoff, no hook validator); RED_TEAM_RESULT at `schema_version: 1` (advisory audit tail, no hook validator); FLOOR_PROJECTION at `schema_version: 1` (added v15.43.0, the derived floor projection `.supervisor/floor/floor.json` emitted by `scripts/build-floor.sh`, no hook validator — standalone script, and not an agent-emitted result block; its required-key set is parsed back OUT of this file by `scripts/test-build-floor.sh`, so a doc/validator divergence fails CI); VERIFY_EVIDENCE at `schema_version: 1` (JSONL state-file line; CLI-gated, no hook validator — `scripts/validate-verify-evidence.py`'s exit status is the gate consumed by `verify-helpers.sh evidence-append`, and it is not an agent-emitted result block); VERIFY_RESULT at `schema_version: 1` (the qa-executor `--verify` mode's result block, added with `/verify`; hook-validated by the SAME `scripts/validate-qa-result.py` command as QA_RESULT — `QA_RESULT` wins whenever present; `counts` copied verbatim from `verify-run.sh finish`, never tallied); all others at `schema_version: 1`.

> **Deliberate exception to the `schema_version` rule above:** `PRODUCT_CONTEXT` (`.agent/product.json`) and `VERIFY_ENV` (`.agent/verify.json`) carry **no** `schema_version` key, so the "all others at `schema_version: 1`" clause does not reach them. Each is a per-project state file committed by the project it describes — not an agent result block and not an artifact this repo ships — so there is no producer/consumer pair inside the plugin for a version number to coordinate; their required-key sets are documented in §PRODUCT_CONTEXT and §VERIFY_ENV and enforced by each reader's own fail-safe degradation, never by a hook.

> **API-level enforcement:** When using the Claude API directly (outside Claude Code), enforce these schemas via `output_config.format` (JSON Schema mode) for guaranteed conformance — the model is constrained to produce schema-valid output before the response is returned. Plugin hook validation (the `SubagentStop` hooks defined in `hooks.json`) is the runtime fallback validator inside Claude Code, where `output_config` is not available to plugin agents. See `AGENT_GUIDELINES.md` §"Structured Outputs" and the Anthropic API reference for the exact field name in your SDK version.

---

## WORKER_RESULT

See [result-schemas/worker-result.md](result-schemas/worker-result.md).

## EXECUTE_RESULT

See [result-schemas/execute-result.md](result-schemas/execute-result.md).

## EXECUTE_CHECKPOINT

See [result-schemas/execute-checkpoint.md](result-schemas/execute-checkpoint.md).

## SUPERVISOR_RESULT

See [result-schemas/supervisor-result.md](result-schemas/supervisor-result.md).

## FIX_RESULT

See [result-schemas/fix-result.md](result-schemas/fix-result.md).

## QA_RESULT

See [result-schemas/qa-result.md](result-schemas/qa-result.md).

## CODE_REVIEW_RESULT

See [result-schemas/code-review-result.md](result-schemas/code-review-result.md).

## PLAN_REVIEW_RESULT

See [result-schemas/plan-review-result.md](result-schemas/plan-review-result.md).

## CONTEXT_KEEPER_STATE

See [result-schemas/context-keeper-state.md](result-schemas/context-keeper-state.md).

## SYSTEM_CONTRACT

See [result-schemas/system-contract.md](result-schemas/system-contract.md).

## `session_end` JSONL hard-signal fields (System Twin)

See [result-schemas/session-end-jsonl.md](result-schemas/session-end-jsonl.md).

## `agent_lifecycle` JSONL event records (waiting / working / failed)

See [result-schemas/agent-lifecycle-jsonl.md](result-schemas/agent-lifecycle-jsonl.md).

## EVAL_RESULT (System Twin eval harness)

See [result-schemas/eval-result.md](result-schemas/eval-result.md).

## GROUND_TRUTH_JSON (System Twin ground-truth runner)

See [result-schemas/ground-truth-json.md](result-schemas/ground-truth-json.md).

## POSTMORTEM_RESULT (PR review-churn analyzer)

See [result-schemas/postmortem-result.md](result-schemas/postmortem-result.md).

## RED_TEAM_RESULT (adversarial audit summary)

See [result-schemas/red-team-result.md](result-schemas/red-team-result.md).

## GATE_VERDICT (pre-execution gate audit)

See [result-schemas/gate-verdict.md](result-schemas/gate-verdict.md).

## QA_SESSION

See [result-schemas/qa-session.md](result-schemas/qa-session.md).

## AUTONOMOUS_RUN

See [result-schemas/autonomous-run.md](result-schemas/autonomous-run.md).

## AUTOMATE_RUN

See [result-schemas/automate-run.md](result-schemas/automate-run.md).

## Schema Versioning

See [result-schemas/schema-versioning.md](result-schemas/schema-versioning.md).

## MISSING_FUNCTIONALITY_REPORT

See [result-schemas/missing-functionality-report.md](result-schemas/missing-functionality-report.md).

## GRAPHQL_RISK_OVERRIDES

See [result-schemas/graphql-risk-overrides.md](result-schemas/graphql-risk-overrides.md).

## LAUNCH_PAD_RESULT

See [result-schemas/launch-pad-result.md](result-schemas/launch-pad-result.md).

## CONTEXT_DIGEST

See [result-schemas/context-digest.md](result-schemas/context-digest.md).

## REVIEW_HEAL_RESULT

See [result-schemas/review-heal-result.md](result-schemas/review-heal-result.md).

## FLOOR_PROJECTION

See [result-schemas/floor-projection.md](result-schemas/floor-projection.md).

## PRODUCT_CONTEXT

See [result-schemas/product-context.md](result-schemas/product-context.md).

## VERIFY_ENV

See [result-schemas/verify-env.md](result-schemas/verify-env.md).

## VERIFY_EVIDENCE

See [result-schemas/verify-evidence.md](result-schemas/verify-evidence.md).

## VERIFY_RESULT

See [result-schemas/verify-result.md](result-schemas/verify-result.md).

## VERIFY_QUEUE

See [result-schemas/verify-queue.md](result-schemas/verify-queue.md).

## MIGRATE_BRANCH_MODE_STATE

See [result-schemas/migrate-branch-mode-state.md](result-schemas/migrate-branch-mode-state.md).

## Validation Location

See [result-schemas/validation-location.md](result-schemas/validation-location.md).

## Cited sub-section anchors

Sub-sections that committed prose cites by name as a section of this file but that are not top-level headings above. Each lives inside the split file named here — open it and search for the anchor text. `scripts/test-result-schemas-split.sh` (check F) derives the cited set from the tracked tree and fails when a cited sub-section is missing from this table or the named file does not hold it.

| Anchor | Split file |
|---|---|
| `## Executable Acceptance` | [result-schemas/ground-truth-json.md](result-schemas/ground-truth-json.md) |
| Completion authority join | [result-schemas/agent-lifecycle-jsonl.md](result-schemas/agent-lifecycle-jsonl.md) |
| `worker_checkpoint` | [result-schemas/agent-lifecycle-jsonl.md](result-schemas/agent-lifecycle-jsonl.md) |
