# QA removal manifest (qa-split item 11a)

The reviewed list of every QA path and named QA reference outside `selvedge/`, each marked `delete`,
`re-point` or `keep`, with the item that acts on it. The old QA system goes in three PRs (plan
`qa-split/00-plan.md`, decisions D1 and Q4): **11b1** removes the agents, commands, skills, hooks and
agent memory; **11b2** removes the scripts, schema docs, blueprint and CI Playwright steps left without a
caller; **12** points the remaining surfaces at Selvedge. Each PR is checked against this list, row by row,
instead of a one-off grep:

```bash
bash loomwright/scripts/check-qa-removal-manifest.sh                # report only, exits 0 (the state before 11b1)
bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b1  # the gate 11b1 must pass
bash loomwright/scripts/check-qa-removal-manifest.sh --expect 11b2  # 11b1 + 11b2 rows
bash loomwright/scripts/check-qa-removal-manifest.sh --expect 12    # every row, re-points included
```

How to read a row (the full format contract is the checker's header comment):

- `delete` — the whole path goes (reference `—`). A path ending in `/` is a directory.
- `re-point` — the file stays, but no longer contains the reference. Checked at `--expect 12` only,
  whatever the row's item; the item names the first PR that has to touch the file (for example 11b1 for
  a count or budget gate, 11b2 for a test that runs a deleted script), and every later PR may finish it.
- `keep` — the path must still exist and, when a reference is given, still contain it. Every keep row is
  item 11b1, so every `--expect` level checks it. Keep rows protect what is not QA (`verify-provides.sh`
  and the `outputs_verified` gate, the `unit-testing` and `quality-checklist` skills), the `qa-executor:`
  Executable Acceptance kind (kept until Phase 3 item 09 or D18 lands), this item's own files, and
  history (the changelog, evidence records, rationale docs, dated spikes, recorded fixtures).

This doc restates no plugin count: the agent, command and skill counts live in the `description` field
of `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, which
`scripts/check-doc-currency.sh` verifies. A row a removal PR finds missing, wrong or over-broad is
changed here in that PR, with the row count below, never worked around.

Row count: 441

## Rows

| path | reference | action | item | reason |
|---|---|---|---|---|
| `.claude/agent-memory/loomwright-loomwright-qa-executor/MEMORY.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/ci_wiring_and_userland_gap.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/count_version_gate_blindspots.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/env_failure_attribution.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/fail_safe_exit_0.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/golden_fixture_regen.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/infra_self_test_contract.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/no_pipe_grep_q_in_tests.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `.claude/agent-memory/loomwright-loomwright-qa-executor/session_end_qa_signal.md` | — | delete | 11b1 | tracked agent-memory file of the removed QA agent (D1) |
| `loomwright/agents/qa-executor.md` | — | delete | 11b1 | QA Executor agent prompt (D1) |
| `loomwright/agents/qa-strategist.md` | — | delete | 11b1 | QA Strategist agent prompt (D1) |
| `loomwright/commands/qa-executor.md` | — | delete | 11b1 | `/qa-executor` command (D1) |
| `loomwright/commands/qa-strategist.md` | — | delete | 11b1 | `/qa-strategist` command (D1) |
| `loomwright/commands/verify.md` | — | delete | 11b1 | `/verify` command (D1); Selvedge replaces it |
| `loomwright/skills/playwright-e2e/` | — | delete | 11b1 | QA skill dir (D1) |
| `loomwright/skills/qa-gates/` | — | delete | 11b1 | QA skill dir (D1) |
| `loomwright/skills/qa-orchestration/` | — | delete | 11b1 | QA skill dir (D1) |
| `loomwright/skills/qa-strategy/` | — | delete | 11b1 | QA skill dir (D1) |
| `loomwright/skills/qa-test-patterns/` | — | delete | 11b1 | QA skill dir (D1) |
| `loomwright/skills/verify-walkthrough/` | — | delete | 11b1 | `/verify` protocol skill dir (D1) |
| `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` | — | delete | 11b2 | design doc of the removed QA system |
| `loomwright/docs/result-schemas/gate-verdict.md` | — | delete | 11b2 | QA schema doc (GATE_VERDICT, QA Strategist gate audit) |
| `loomwright/docs/result-schemas/graphql-risk-overrides.md` | — | delete | 11b2 | QA schema doc (GRAPHQL_RISK_OVERRIDES, QA Strategist output) |
| `loomwright/docs/result-schemas/missing-functionality-report.md` | — | delete | 11b2 | QA schema doc (MISSING_FUNCTIONALITY_REPORT, QA Executor output) |
| `loomwright/docs/result-schemas/qa-result.md` | — | delete | 11b2 | QA schema doc (QA_RESULT) |
| `loomwright/docs/result-schemas/qa-session.md` | — | delete | 11b2 | QA schema doc (QA_SESSION) |
| `loomwright/docs/result-schemas/verify-env.md` | — | delete | 11b2 | verify schema doc (VERIFY_ENV) |
| `loomwright/docs/result-schemas/verify-evidence.md` | — | delete | 11b2 | verify schema doc (VERIFY_EVIDENCE) |
| `loomwright/docs/result-schemas/verify-queue.md` | — | delete | 11b2 | verify schema doc (VERIFY_QUEUE) |
| `loomwright/docs/result-schemas/verify-result.md` | — | delete | 11b2 | verify schema doc (VERIFY_RESULT) |
| `loomwright/scripts/propose-verify.sh` | — | delete | 11b2 | writer of the old `/verify` env contract; it needs `read-verify.sh`, so it goes in the same PR |
| `loomwright/scripts/read-playwright-pin.sh` | — | delete | 11b2 | derives the CI Playwright cache key; goes with the CI steps |
| `loomwright/scripts/read-verify.sh` | — | delete | 11b2 | reader of the old `/verify` env contract |
| `loomwright/scripts/result-validator-fixtures/qa-result-valid.md` | — | delete | 11b2 | fixture of the deleted QA validator |
| `loomwright/scripts/test-read-playwright-pin.sh` | — | delete | 11b2 | self-test of a deleted script |
| `loomwright/scripts/test-verify-evidence.sh` | — | delete | 11b2 | self-test of a deleted script |
| `loomwright/scripts/test-verify-queue.sh` | — | delete | 11b2 | self-test of deleted `/verify` scripts |
| `loomwright/scripts/test-verify-seam.sh` | — | delete | 11b2 | self-test of deleted `/verify` scripts |
| `loomwright/scripts/test-verify-walkthrough.sh` | — | delete | 11b2 | self-test of deleted `/verify` scripts (the Playwright download path) |
| `loomwright/scripts/validate-qa-result.py` | — | delete | 11b2 | SubagentStop validator of the removed QA agent; no caller after 11b1 |
| `loomwright/scripts/validate-verify-evidence.py` | — | delete | 11b2 | `/verify` evidence validator; no caller after 11b1 |
| `loomwright/scripts/verify-env.sh` | — | delete | 11b2 | `/verify` environment runner; no caller after 11b1 |
| `loomwright/scripts/verify-fixture-app.py` | — | delete | 11b2 | `/verify` test fixture app |
| `loomwright/scripts/verify-helpers.sh` | — | delete | 11b2 | `/verify` helper library; no caller after 11b1 |
| `loomwright/scripts/verify-run.sh` | — | delete | 11b2 | `/verify` executor; no caller after 11b1 |
| `loomwright/docs/command-parts/agent-help/qa.md` | — | delete | 12 | the QA topic page of `/agent-help`; goes with the `agent-help` re-point |
| `loomwright/scripts/telemetry-fixtures/golden/qa-failed__allow_with_repo.golden.txt` | — | delete | 12 | golden output of the QA telemetry fixture; 11b2 refreshed it to the fail-safe `validator_unavailable schema=QA_RESULT` line its deleted validator now yields |
| `loomwright/scripts/telemetry-fixtures/qa-failed.json` | — | delete | 12 | telemetry fixture for the QA_RESULT rubric; goes with the telemetry name-map re-point |
| `.claude-plugin/README.md` | `.qa-summary` | re-point | 11b1 | names a QA run artifact |
| `.claude-plugin/README.md` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `.claude-plugin/README.md` | `QA Executor` | re-point | 11b1 | names a removed QA agent |
| `.claude-plugin/README.md` | `QA Strategist` | re-point | 11b1 | names a removed QA agent |
| `.claude-plugin/README.md` | `QA_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `.claude-plugin/README.md` | `QA_SYSTEM_BLUEPRINT` | re-point | 11b2 | names the QA design doc 11b2 deletes |
| `.claude-plugin/README.md` | `STRATEGIST_VERDICT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `.claude-plugin/README.md` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `.claude-plugin/README.md` | `qa-strategist` | re-point | 11b1 | names a removed QA agent |
| `.claude-plugin/README.md` | `validate-qa-result.py` | re-point | 11b1 | names a QA script 11b2 deletes |
| `.claude-plugin/marketplace.json` | `"playwright"` | re-point | 11b1 | loomwright keyword for the removed QA system |
| `.claude-plugin/marketplace.json` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `.claude-plugin/marketplace.json` | `qa-strategist` | re-point | 11b1 | names a removed QA agent |
| `.claude-plugin/marketplace.json` | `red-teaming, QA,` | re-point | 11b1 | loomwright description names QA; its agent, command and skill counts drop in the same PR (verified by `check-doc-currency.sh`, not restated here) |
| `.github/workflows/ci.yml` | `LOOMWRIGHT_VERIFY` | re-point | 11b2 | CI Playwright pin and cache steps: the `/verify` test cache variable |
| `.github/workflows/ci.yml` | `read-playwright-pin.sh` | re-point | 11b2 | CI Playwright pin and cache steps: names a QA script 11b2 deletes |
| `.github/workflows/ci.yml` | `verify-walkthrough` | re-point | 11b2 | CI Playwright pin and cache steps: names a removed QA skill or its test |
| `AGENT_GUIDELINES.md` | `.agent/verify.json` | re-point | 12 | names the old `/verify` env contract path |
| `AGENT_GUIDELINES.md` | `.qa-summary` | re-point | 12 | names a QA run artifact |
| `AGENT_GUIDELINES.md` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `AGENT_GUIDELINES.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `AGENT_GUIDELINES.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `AGENT_GUIDELINES.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `AGENT_GUIDELINES.md` | `QA_SESSION` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `AGENT_GUIDELINES.md` | `STRATEGIST_VERDICT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `AGENT_GUIDELINES.md` | `VERIFY_ENV` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `AGENT_GUIDELINES.md` | `propose-verify.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `AGENT_GUIDELINES.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `AGENT_GUIDELINES.md` | `qa-strategist` | re-point | 12 | names a removed QA agent |
| `AGENT_GUIDELINES.md` | `read-verify.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `CLAUDE.md` | `QA Executor` | re-point | 11b1 | agent-roles table / references: names a removed QA agent |
| `CLAUDE.md` | `QA Strategist` | re-point | 11b1 | agent-roles table / references: names a removed QA agent |
| `CLAUDE.md` | `QA_SYSTEM_BLUEPRINT` | re-point | 11b2 | agent-roles table / references: names the QA design doc 11b2 deletes |
| `README.md` | `.qa-session` | re-point | 11b1 | names a QA run artifact |
| `README.md` | `.qa-summary` | re-point | 11b1 | names a QA run artifact |
| `README.md` | `/verify` | re-point | 11b1 | names the removed `/verify` command |
| `README.md` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `README.md` | `QA Executor` | re-point | 11b1 | names a removed QA agent |
| `README.md` | `QA Strategist` | re-point | 11b1 | names a removed QA agent |
| `README.md` | `QA_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `README.md` | `QA_SYSTEM_BLUEPRINT` | re-point | 11b2 | names the QA design doc 11b2 deletes |
| `README.md` | `STRATEGIST_VERDICT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `README.md` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `README.md` | `qa-strategist` | re-point | 11b1 | names a removed QA agent |
| `loomwright/.claude-plugin/plugin.json` | `"debate-loop"` | re-point | 11b1 | keyword for the removed QA system |
| `loomwright/.claude-plugin/plugin.json` | `"e2e-testing"` | re-point | 11b1 | keyword for the removed QA system |
| `loomwright/.claude-plugin/plugin.json` | `"playwright"` | re-point | 11b1 | keyword for the removed QA system |
| `loomwright/.claude-plugin/plugin.json` | `"risk-based-testing"` | re-point | 11b1 | keyword for the removed QA system |
| `loomwright/.claude-plugin/plugin.json` | `"test-generation"` | re-point | 11b1 | keyword for the removed QA system |
| `loomwright/.claude-plugin/plugin.json` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/.claude-plugin/plugin.json` | `qa-strategist` | re-point | 11b1 | names a removed QA agent |
| `loomwright/.claude-plugin/plugin.json` | `red-teaming, QA,` | re-point | 11b1 | description names QA; its agent, command and skill counts drop in the same PR (verified by `check-doc-currency.sh`, not restated here) |
| `loomwright/capabilities.json` | `/verify` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names the removed `/verify` command |
| `loomwright/capabilities.json` | `GATE_VERDICT` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `GRAPHQL_RISK_OVERRIDES` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `QA Executor` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA agent |
| `loomwright/capabilities.json` | `QA_RESULT` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `QA_SESSION` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `VERIFY_ENV` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `VERIFY_EVIDENCE` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `VERIFY_QUEUE` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `VERIFY_RESULT` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA or verify schema 11b2 deletes |
| `loomwright/capabilities.json` | `playwright-e2e` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA skill |
| `loomwright/capabilities.json` | `qa-executor` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA agent |
| `loomwright/capabilities.json` | `qa-gates` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA skill |
| `loomwright/capabilities.json` | `qa-orchestration` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA skill |
| `loomwright/capabilities.json` | `qa-strategist` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA agent |
| `loomwright/capabilities.json` | `qa-strategy` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA skill |
| `loomwright/capabilities.json` | `qa-test-patterns` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA skill |
| `loomwright/capabilities.json` | `validate-qa-result.py` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a QA script 11b2 deletes |
| `loomwright/capabilities.json` | `verify-walkthrough` | re-point | 11b1 | generated from the agents, commands and skills; regenerate: names a removed QA skill or its test |
| `loomwright/commands/agent-help.md` | `/verify` | re-point | 12 | agent-help: names the removed `/verify` command |
| `loomwright/commands/agent-help.md` | `QA Executor` | re-point | 12 | agent-help: names a removed QA agent |
| `loomwright/commands/agent-help.md` | `QA Strategist` | re-point | 12 | agent-help: names a removed QA agent |
| `loomwright/commands/agent-help.md` | `QA_RESULT` | re-point | 12 | agent-help: names a QA or verify schema 11b2 deletes |
| `loomwright/commands/agent-help.md` | `agent-help/qa.md` | re-point | 12 | agent-help: names the QA help page 12 deletes |
| `loomwright/commands/agent-help.md` | `qa-executor` | re-point | 12 | agent-help: names a removed QA agent |
| `loomwright/commands/agent-help.md` | `qa-strategist` | re-point | 12 | agent-help: names a removed QA agent |
| `loomwright/commands/propose.md` | `/verify` | re-point | 12 | `/propose --from-verify` text: names the removed `/verify` command |
| `loomwright/commands/propose.md` | `VERIFY_EVIDENCE` | re-point | 12 | `/propose --from-verify` text: names a QA or verify schema 11b2 deletes |
| `loomwright/commands/propose.md` | `read-verify.sh` | re-point | 12 | `/propose --from-verify` text: names a QA script 11b2 deletes |
| `loomwright/commands/propose.md` | `verify-helpers.sh` | re-point | 12 | `/propose --from-verify` text: names a QA script 11b2 deletes |
| `loomwright/commands/propose.md` | `verify-run.sh` | re-point | 12 | `/propose --from-verify` text: names a QA script 11b2 deletes |
| `loomwright/docs/ARCHITECTURE.md` | `.qa-summary` | re-point | 12 | names a QA run artifact |
| `loomwright/docs/ARCHITECTURE.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/ARCHITECTURE.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/ARCHITECTURE.md` | `QA_SYSTEM_BLUEPRINT` | re-point | 12 | names the QA design doc 11b2 deletes |
| `loomwright/docs/ARCHITECTURE.md` | `STRATEGIST_VERDICT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/ARCHITECTURE.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/ARCHITECTURE.md` | `qa-strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `.qa-summary` | re-point | 11b1 | includes the token-budget mirror table: names a QA run artifact |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `QA Executor` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA agent |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `QA Strategist` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA agent |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `QA_RESULT` | re-point | 11b1 | includes the token-budget mirror table: names a QA or verify schema 11b2 deletes |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `` `/verify` `` | re-point | 11b1 | question-gate inventory rows of the removed `/verify` command (the file also names `verify-provides.sh`, so the backticked form is the reference) |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `` `verify` `` | re-point | 11b1 | token-budget mirror row of the removed `/verify` command |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `commands/verify.md` | re-point | 11b1 | includes the token-budget mirror table: names the removed `/verify` command |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `playwright-e2e` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA skill |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `qa-executor` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA agent |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `qa-gates` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA skill |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `qa-orchestration` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA skill |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `qa-strategist` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA agent |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `qa-strategy` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA skill |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `qa-test-patterns` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA skill |
| `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | `verify-walkthrough` | re-point | 11b1 | includes the token-budget mirror table: names a removed QA skill or its test |
| `loomwright/docs/CAPABILITIES_CONTRACT.md` | `GATE_VERDICT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/CAPABILITIES_CONTRACT.md` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/CAPABILITIES_CONTRACT.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/CAPABILITIES_CONTRACT.md` | `VERIFY_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/CAPABILITIES_CONTRACT.md` | `validate-qa-result.py` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/FAILURE_ESCALATION.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/FAILURE_ESCALATION.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/FAILURE_ESCALATION.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/HOOKS.md` | `QA Executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/docs/HOOKS.md` | `QA_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/HOOKS.md` | `VERIFY_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/HOOKS.md` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/docs/HOOKS.md` | `qa-strategist` | re-point | 11b1 | names a removed QA agent |
| `loomwright/docs/HOOKS.md` | `validate-qa-result.py` | re-point | 11b1 | names a QA script 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `.agent/verify.json` | re-point | 11b2 | names the old `/verify` env contract path |
| `loomwright/docs/RESULT_SCHEMAS.md` | `/verify` | re-point | 11b2 | names the removed `/verify` command |
| `loomwright/docs/RESULT_SCHEMAS.md` | `GATE_VERDICT` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `GRAPHQL_RISK_OVERRIDES` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `QA_RESULT` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `QA_SESSION` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `VERIFY_ENV` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `VERIFY_EVIDENCE` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `VERIFY_QUEUE` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `VERIFY_RESULT` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `qa-executor` | re-point | 11b2 | names a removed QA agent |
| `loomwright/docs/RESULT_SCHEMAS.md` | `validate-qa-result.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `validate-verify-evidence.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `verify-helpers.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/docs/RESULT_SCHEMAS.md` | `verify-run.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/docs/TELEMETRY.md` | `/verify` | re-point | 12 | names the removed `/verify` command |
| `loomwright/docs/TELEMETRY.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/TELEMETRY.md` | `VERIFY_EVIDENCE` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/TELEMETRY.md` | `commands/verify.md` | re-point | 12 | names the removed `/verify` command |
| `loomwright/docs/TELEMETRY.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/TELEMETRY.md` | `qa-strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/TELEMETRY.md` | `validate-qa-result.py` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/TELEMETRY.md` | `verify-helpers.sh` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/TELEMETRY.md` | `verify-run.sh` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/command-parts/agent-help/guide.md` | `.qa-summary` | re-point | 12 | names a QA run artifact |
| `loomwright/docs/command-parts/agent-help/guide.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/agent-help/guide.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/agent-help/guide.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/command-parts/agent-help/guide.md` | `QA_SYSTEM_BLUEPRINT` | re-point | 12 | names the QA design doc 11b2 deletes |
| `loomwright/docs/command-parts/agent-help/guide.md` | `STRATEGIST_VERDICT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/command-parts/agent-help/guide.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/agent-help/guide.md` | `qa-strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/agent-help/knowledge.md` | `/verify` | re-point | 12 | names the removed `/verify` command |
| `loomwright/docs/command-parts/agent-help/knowledge.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/agent-help/knowledge.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/agent-help/more.md` | `.qa-summary` | re-point | 12 | names a QA run artifact |
| `loomwright/docs/command-parts/agent-help/more.md` | `STRATEGIST_VERDICT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/command-parts/agent-help/more.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/agent-help/more.md` | `qa-strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/overview.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/overview.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/overview.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/command-parts/dreaming/overview.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/read-only.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/reference.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/reference.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/reference.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/command-parts/dreaming/reflection-prompt.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/agents/qa-executor.md` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/agents/qa-strategist.md` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/commands/qa-executor.md` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/commands/qa-strategist.md` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/commands/verify.md` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/docs/command-parts/agent-help/qa.md` | re-point | 12 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/skills/playwright-e2e` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/skills/qa-gates` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/skills/qa-orchestration` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/skills/qa-strategy` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/skills/qa-test-patterns` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/skills/verify-walkthrough` | re-point | 11b1 | prompt-history baseline entry of a deleted prompt |
| `loomwright/docs/prompt-token-budgets.json` | `"verify": {` | re-point | 11b1 | token-budget entry of the removed `/verify` command |
| `loomwright/docs/prompt-token-budgets.json` | `playwright-e2e` | re-point | 11b1 | token-budget entry: names a removed QA skill |
| `loomwright/docs/prompt-token-budgets.json` | `qa-executor` | re-point | 11b1 | token-budget entry: names a removed QA agent |
| `loomwright/docs/prompt-token-budgets.json` | `qa-gates` | re-point | 11b1 | token-budget entry: names a removed QA skill |
| `loomwright/docs/prompt-token-budgets.json` | `qa-orchestration` | re-point | 11b1 | token-budget entry: names a removed QA skill |
| `loomwright/docs/prompt-token-budgets.json` | `qa-strategist` | re-point | 11b1 | token-budget entry: names a removed QA agent |
| `loomwright/docs/prompt-token-budgets.json` | `qa-strategy` | re-point | 11b1 | token-budget entry: names a removed QA skill |
| `loomwright/docs/prompt-token-budgets.json` | `qa-test-patterns` | re-point | 11b1 | token-budget entry: names a removed QA skill |
| `loomwright/docs/prompt-token-budgets.json` | `verify-walkthrough` | re-point | 11b1 | token-budget entry: names a removed QA skill or its test |
| `loomwright/docs/result-schemas/agent-lifecycle-jsonl.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/result-schemas/automate-run/crash-safety.md` | `VERIFY_QUEUE` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/execute-result.md` | `/verify` | re-point | 12 | names the removed `/verify` command |
| `loomwright/docs/result-schemas/execute-result.md` | `verify-run.sh` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/result-schemas/migrate-branch-mode-state.md` | `VERIFY_QUEUE` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `/verify` | re-point | 12 | names the removed `/verify` command |
| `loomwright/docs/result-schemas/schema-versioning.md` | `GRAPHQL_RISK_OVERRIDES` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/result-schemas/schema-versioning.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/result-schemas/schema-versioning.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `QA_SESSION` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `VERIFY_EVIDENCE` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `VERIFY_QUEUE` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `VERIFY_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `(qa-executor)` | re-point | 12 | names the removed QA agent's validator matcher (the file's other `qa-executor` mentions are the kept kind; see its keep row) |
| `loomwright/docs/result-schemas/schema-versioning.md` | `validate-qa-result.py` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `validate-verify-evidence.py` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `verify-helpers.sh` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/result-schemas/schema-versioning.md` | `verify-run.sh` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/result-schemas/supervisor-result.md` | `.agent/verify.json` | re-point | 12 | names the old `/verify` env contract path |
| `loomwright/docs/result-schemas/validation-location.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/result-schemas/validation-location.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/validation-location.md` | `VERIFY_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/docs/result-schemas/validation-location.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/docs/result-schemas/validation-location.md` | `validate-qa-result.py` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/agents/qa-executor.md` | re-point | 11b1 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/agents/qa-strategist.md` | re-point | 11b1 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/commands/qa-executor.md` | re-point | 11b1 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/commands/verify.md` | re-point | 11b1 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/docs/QA_SYSTEM_BLUEPRINT.md` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/docs/command-parts/agent-help/qa.md` | re-point | 12 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/docs/result-schemas/qa-result.md` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/docs/result-schemas/verify-evidence.md` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/docs/result-schemas/verify-queue.md` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/docs/result-schemas/verify-result.md` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/scripts/test-verify-walkthrough.sh` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/scripts/validate-qa-result.py` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/scripts/validate-verify-evidence.py` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/scripts/verify-helpers.sh` | re-point | 11b2 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/docs/vendor-coupling-manifest.json` | `loomwright/skills/verify-walkthrough` | re-point | 11b1 | vendor-coupling allowance of a deleted path; a stale entry fails `check-vendor-coupling.sh` |
| `loomwright/hooks/hooks.json` | `qa-executor` | re-point | 11b1 | SubagentStop matcher: names a removed QA agent |
| `loomwright/hooks/hooks.json` | `qa-strategist` | re-point | 11b1 | SubagentStop matcher: names a removed QA agent |
| `loomwright/hooks/hooks.json` | `validate-qa-result.py` | re-point | 11b1 | SubagentStop matcher: names a QA script 11b2 deletes |
| `loomwright/scripts/adapters/providers/lens-roles.sh` | `qa_strategist` | re-point | 12 | provider routing role map: names a removed QA agent (derived key) |
| `loomwright/scripts/adapters/providers/test-lens-roles.sh` | `qa_strategist` | re-point | 12 | names a removed QA agent (derived key) |
| `loomwright/scripts/build-capabilities.sh` | `GATE_VERDICT` | re-point | 12 | capabilities name map (validator table): names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/build-capabilities.sh` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 12 | capabilities name map (validator table): names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/build-capabilities.sh` | `QA_RESULT` | re-point | 12 | capabilities name map (validator table): names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/build-capabilities.sh` | `VERIFY_RESULT` | re-point | 12 | capabilities name map (validator table): names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/build-capabilities.sh` | `qa-executor` | re-point | 12 | capabilities name map (validator table): names a removed QA agent |
| `loomwright/scripts/build-capabilities.sh` | `validate-qa-result.py` | re-point | 12 | capabilities name map (validator table): names a QA script 11b2 deletes |
| `loomwright/scripts/classify-risk.sh` | `.agent/verify.json` | re-point | 12 | trusted root-only path; 12 swaps it for `selvedge.json`: names the old `/verify` env contract path |
| `loomwright/scripts/emit-token-ledger.sh` | `qa-executor` | re-point | 12 | token-ledger name map: names a removed QA agent |
| `loomwright/scripts/fixtures/command-parts/move-only.txt` | `agent-help/qa.md` | re-point | 12 | names the QA help page 12 deletes |
| `loomwright/scripts/fixtures/self-test-weights.tsv` | `read-playwright-pin.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/fixtures/self-test-weights.tsv` | `verify-walkthrough` | re-point | 11b2 | names a removed QA skill or its test |
| `loomwright/scripts/notify-desktop.sh` | `qa-executor` | re-point | 12 | notify name map: names a removed QA agent |
| `loomwright/scripts/notify-desktop.sh` | `qa-strategist` | re-point | 12 | notify name map: names a removed QA agent |
| `loomwright/scripts/propose-from-verify.sh` | `/verify` | re-point | 12 | `/propose --from-verify` reads `/verify` evidence; 12 points it at Selvedge's verdict file: names the removed `/verify` command |
| `loomwright/scripts/propose-from-verify.sh` | `VERIFY_EVIDENCE` | re-point | 12 | `/propose --from-verify` reads `/verify` evidence; 12 points it at Selvedge's verdict file: names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/propose-from-verify.sh` | `verify-helpers.sh` | re-point | 12 | `/propose --from-verify` reads `/verify` evidence; 12 points it at Selvedge's verdict file: names a QA script 11b2 deletes |
| `loomwright/scripts/resolve-routing.sh` | `qa-strategist` | re-point | 12 | provider routing seat table: names a removed QA agent |
| `loomwright/scripts/resolve-routing.sh` | `qa_strategist` | re-point | 12 | provider routing seat table: names a removed QA agent (derived key) |
| `loomwright/scripts/result_block_parser.py` | `QA_RESULT` | re-point | 12 | result-block name map: names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/result_block_parser.py` | `qa-executor` | re-point | 12 | result-block name map: names a removed QA agent |
| `loomwright/scripts/send-telemetry-core.sh` | `QA_RESULT` | re-point | 12 | telemetry name map (schema to validator): names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/send-telemetry-core.sh` | `qa-executor` | re-point | 12 | telemetry name map (schema to validator): names a removed QA agent |
| `loomwright/scripts/send-telemetry-core.sh` | `validate-qa-result.py` | re-point | 12 | telemetry name map (schema to validator): names a QA script 11b2 deletes |
| `loomwright/scripts/send-webhook.sh` | `qa-executor` | re-point | 12 | webhook name map: names a removed QA agent |
| `loomwright/scripts/send-webhook.sh` | `qa-strategist` | re-point | 12 | webhook name map: names a removed QA agent |
| `loomwright/scripts/send-webhook.sh` | `verify-helpers.sh` | re-point | 12 | webhook name map: names a QA script 11b2 deletes |
| `loomwright/scripts/test-agent-memory-permission.sh` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/scripts/test-agent-memory-permission.sh` | `qa-strategist` | re-point | 11b1 | names a removed QA agent |
| `loomwright/scripts/test-automate-helpers.d/07-rules-gate.sh` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/scripts/test-base-branch-single-resolver.sh` | `verify-run.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-build-capabilities.sh` | `GATE_VERDICT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-build-capabilities.sh` | `MISSING_FUNCTIONALITY_REPORT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-build-capabilities.sh` | `QA_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-build-capabilities.sh` | `VERIFY_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-build-capabilities.sh` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/scripts/test-build-capabilities.sh` | `qa-strategist` | re-point | 11b1 | names a removed QA agent |
| `loomwright/scripts/test-check-contract-parity.sh` | `QA_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-check-contract-parity.sh` | `VERIFY_RESULT` | re-point | 11b1 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-check-contract-parity.sh` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/scripts/test-check-contract-parity.sh` | `validate-qa-result.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-committed-twin-scrub.sh` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/scripts/test-emit-block-parses.sh` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-emit-block-parses.sh` | `VERIFY_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-harvest-conventions.sh` | `golden_fixture_regen` | re-point | 11b1 | scored a deleted QA agent-memory entry as its worked example |
| `loomwright/scripts/test-insights.sh` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/scripts/test-no-fixed-sleep-race.sh` | `verify-walkthrough` | re-point | 11b2 | names a removed QA skill or its test |
| `loomwright/scripts/test-no-pipefail-grep-q.sh` | `verify-run.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-non-interactive-gates-seam.sh` | `qa-executor` | re-point | 11b1 | names a removed QA agent |
| `loomwright/scripts/test-not-verified-transport-seam.sh` | `/verify` | re-point | 12 | names the removed `/verify` command |
| `loomwright/scripts/test-not-verified-transport-seam.sh` | `verify-run.sh` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-not-verified-transport-seam.sh` | `verify-walkthrough` | re-point | 12 | names a removed QA skill or its test |
| `loomwright/scripts/test-proc-registry.sh` | `verify-fixture-app.py` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-propose-from-verify.sh` | `VERIFY_EVIDENCE` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-propose-from-verify.sh` | `validate-verify-evidence.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-propose-from-verify.sh` | `verify-helpers.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-result-validators.sh` | `QA_RESULT` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-result-validators.sh` | `VERIFY_RESULT` | re-point | 11b2 | names a QA or verify schema 11b2 deletes |
| `loomwright/scripts/test-result-validators.sh` | `qa-executor` | re-point | 11b2 | names a removed QA agent |
| `loomwright/scripts/test-result-validators.sh` | `validate-qa-result.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-result-validators.sh` | `verify-run.sh` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-script-event-telemetry.sh` | `validate-qa-result.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-send-telemetry-core.sh` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/scripts/test-send-telemetry-core.sh` | `validate-qa-result.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-telemetry-threads.sh` | `validate-qa-result.py` | re-point | 11b2 | names a QA script 11b2 deletes |
| `loomwright/scripts/test-telemetry.sh` | `qa-failed` | re-point | 12 | names the QA telemetry fixture 12 deletes |
| `loomwright/scripts/test-token-ledger.sh` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `loomwright/scripts/write-agent-memory.sh` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/skills/SKILLS_INDEX.md` | `/verify` | re-point | 11b1 | skills index row: names the removed `/verify` command |
| `loomwright/skills/SKILLS_INDEX.md` | `QA Executor` | re-point | 11b1 | skills index row: names a removed QA agent |
| `loomwright/skills/SKILLS_INDEX.md` | `QA Strategist` | re-point | 11b1 | skills index row: names a removed QA agent |
| `loomwright/skills/SKILLS_INDEX.md` | `playwright-e2e` | re-point | 11b1 | skills index row: names a removed QA skill |
| `loomwright/skills/SKILLS_INDEX.md` | `qa-gates` | re-point | 11b1 | skills index row: names a removed QA skill |
| `loomwright/skills/SKILLS_INDEX.md` | `qa-orchestration` | re-point | 11b1 | skills index row: names a removed QA skill |
| `loomwright/skills/SKILLS_INDEX.md` | `qa-strategy` | re-point | 11b1 | skills index row: names a removed QA skill |
| `loomwright/skills/SKILLS_INDEX.md` | `qa-test-patterns` | re-point | 11b1 | skills index row: names a removed QA skill |
| `loomwright/skills/SKILLS_INDEX.md` | `verify-walkthrough` | re-point | 11b1 | skills index row: names a removed QA skill or its test |
| `loomwright/skills/ci-cd/SKILL.md` | `playwright-e2e` | re-point | 12 | names a removed QA skill |
| `loomwright/skills/memory-tool/SKILL.md` | `QA Executor` | re-point | 12 | names a removed QA agent |
| `loomwright/skills/memory-tool/SKILL.md` | `QA Strategist` | re-point | 12 | names a removed QA agent |
| `loomwright/skills/self-heal-advisory/completion-tail.md` | `/verify` | re-point | 12 | names the removed `/verify` command |
| `loomwright/skills/self-heal-advisory/completion-tail.md` | `verify-run.sh` | re-point | 12 | names a QA script 11b2 deletes |
| `loomwright/skills/telemetry/SKILL.md` | `QA_RESULT` | re-point | 12 | names a QA or verify schema 11b2 deletes |
| `loomwright/skills/unit-testing/SKILL.md` | `playwright-e2e` | re-point | 12 | names a removed QA skill |
| `loomwright/skills/workflow-management/SKILL.md` | `qa-executor` | re-point | 12 | names a removed QA agent |
| `scripts/check-contract-parity.sh` | `QA_RESULT` | re-point | 11b1 | contract-parity table: names a QA or verify schema 11b2 deletes |
| `scripts/check-contract-parity.sh` | `VERIFY_RESULT` | re-point | 11b1 | contract-parity table: names a QA or verify schema 11b2 deletes |
| `scripts/check-contract-parity.sh` | `qa-executor` | re-point | 11b1 | contract-parity table: names a removed QA agent |
| `scripts/check-contract-parity.sh` | `validate-qa-result.py` | re-point | 11b2 | contract-parity table: names a QA script 11b2 deletes |
| `scripts/ci-local.sh` | `playwright pin` | re-point | 11b2 | comment names the CI Playwright pin step 11b2 deletes |
| `scripts/test-ci-local.sh` | `verify-walkthrough` | re-point | 11b2 | names a removed QA skill or its test |
| `.claude/agent-memory/loomwright-loomwright-code-reviewer/jsonl-appender-accepts-multiline-input.md` | — | keep | 11b1 | code-reviewer memory: a lesson whose incident was in a deleted helper (history) |
| `CHANGELOG.md` | — | keep | 11b1 | release history; past entries stay as written |
| `docs/evidence/as15-diet-supervisor.md` | — | keep | 11b1 | evidence record (history) |
| `docs/evidence/as22-split-big-commands.md` | — | keep | 11b1 | evidence record (history) |
| `docs/evidence/as24-terse-script-output.md` | — | keep | 11b1 | evidence record (history) |
| `docs/evidence/dismissed-followups-06a-docs.md` | — | keep | 11b1 | evidence record (history) |
| `docs/evidence/dismissed-followups-06a-scripts.md` | — | keep | 11b1 | evidence record (history) |
| `docs/evidence/dismissed-followups-06b-docs.md` | — | keep | 11b1 | evidence record (history) |
| `docs/evidence/pa18b-right-size-check.md` | — | keep | 11b1 | evidence record (history) |
| `docs/evidence/qa-split-11b1-removal.md` | — | keep | 11b1 | evidence record (history by design) |
| `docs/evidence/review-gate-rounds.md` | — | keep | 11b1 | evidence record (history) |
| `loomwright/agents/execute-manager.md` | `outputs_verified gate` | keep | 11b1 | home of the `outputs_verified` gate (the per-subtask gate); not QA |
| `loomwright/agents/launch-pad.md` | `qa-executor:` | keep | 11b1 | keeps `qa-executor:` bullets when stripping `cmd:` bullets; kept until Phase 3 item 09 or D18 |
| `loomwright/agents/plan-reviewer.md` | `qa-executor:` | keep | 11b1 | classifier sentence names the kept `qa-executor:` prefix; kept until Phase 3 item 09 or D18 |
| `loomwright/docs/IMPROVEMENTS_ROADMAP.md` | — | keep | 11b1 | dated roadmap with resolved verdicts (history) |
| `loomwright/docs/POINTER_AUDIT.md` | — | keep | 11b1 | dated audit record (history) |
| `loomwright/docs/SPIKES/BRAIN_INTEGRATION_EVOLUTION.md` | — | keep | 11b1 | dated spike (history) |
| `loomwright/docs/SPIKES/CODE_GRAPH_OWNERSHIP.md` | — | keep | 11b1 | dated spike (history) |
| `loomwright/docs/SPIKES/EVAL_FINDINGS_AND_FIXES.md` | — | keep | 11b1 | dated spike (history) |
| `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` | — | keep | 11b1 | dated spike (history) |
| `loomwright/docs/SPIKES/LOCAL_TWIN_PATH.md` | — | keep | 11b1 | dated spike (history) |
| `loomwright/docs/SPIKES/QA_AND_DURABILITY_BACKLOG.md` | — | keep | 11b1 | dated spike (history; superseded by the qa-split plan) |
| `loomwright/docs/SPIKES/SYSTEM_TWIN_ROADMAP.md` | — | keep | 11b1 | dated spike (history) |
| `loomwright/docs/loop-inventory/launch-pad-autonomous.md` | `qa-executor:` | keep | 11b1 | inventory row for the kept `qa-executor:` bullets; kept until Phase 3 item 09 or D18 |
| `loomwright/docs/loop-inventory/supervisor.md` | `qa-executor:` | keep | 11b1 | inventory row for the deferred `qa-executor:` checks; kept until Phase 3 item 09 or D18 |
| `loomwright/docs/qa-removal-manifest.md` | — | keep | 11b1 | this manifest: the reviewed list 11b1, 11b2 and 12 are checked against |
| `loomwright/docs/rationale/automate-loop.md` | — | keep | 11b1 | rationale doc (history by design) |
| `loomwright/docs/rationale/launch-pad-autonomous.md` | — | keep | 11b1 | rationale doc (history by design) |
| `loomwright/docs/rationale/qa-split.md` | — | keep | 11b1 | rationale doc (history by design) |
| `loomwright/docs/rationale/subagents.md` | — | keep | 11b1 | rationale doc (history by design) |
| `loomwright/docs/result-schemas/ground-truth-json.md` | `qa-executor:` | keep | 11b1 | schema of the kept `qa-executor:` kind; kept until Phase 3 item 09 or D18 |
| `loomwright/docs/result-schemas/schema-versioning.md` | `cmd\|corpus-task\|qa-executor` | keep | 11b1 | the GROUND_TRUTH_JSON entry's kind enum names the kept `qa-executor` kind; kept until Phase 3 item 09 or D18 |
| `loomwright/docs/result-schemas/supervisor-result.md` | `qa-executor` | keep | 11b1 | its one `qa-executor` mention is the deferred kind; kept until Phase 3 item 09 or D18 |
| `loomwright/scripts/automate-dismissed.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/automate-helpers.d/plan-waves.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/check-qa-removal-manifest.sh` | — | keep | 11b1 | the checker of this manifest |
| `loomwright/scripts/exec-acceptance-hash.sh` | `qa-executor:` | keep | 11b1 | documents the kept `qa-executor:` Executable Acceptance kind; kept until Phase 3 item 09 or D18 |
| `loomwright/scripts/exec-acceptance-lib.sh` | `qa-executor:*)` | keep | 11b1 | `classify_kind`'s `qa-executor` arm: kept until Phase 3 item 09 or D18 lands (owner decision 2026-11-12) |
| `loomwright/scripts/fixtures/closed-enum-pins/brief-plain.md` | — | keep | 11b1 | sample brief text in a fixture; QA names are its content, not a coupling |
| `loomwright/scripts/fixtures/corpus-briefs/done/2026-09-15-verify-auth-pause.md` | — | keep | 11b1 | recorded done-brief in the eval corpus (fixture data) |
| `loomwright/scripts/fixtures/corpus-briefs/done/2026-09-16-verify-impact-pass.md` | — | keep | 11b1 | recorded done-brief in the eval corpus (fixture data) |
| `loomwright/scripts/fixtures/escalation-cause/s2c-log-failed.txt` | — | keep | 11b1 | recorded CI log (fixture data) |
| `loomwright/scripts/fixtures/harvest-ledger/results.jsonl` | — | keep | 11b1 | recorded PR path lists (fixture data) |
| `loomwright/scripts/fixtures/pr-body-evidence/brief-evidence-file.md` | — | keep | 11b1 | sample brief text in a fixture; QA names are its content |
| `loomwright/scripts/fixtures/pr-body-evidence/brief-pr-body.md` | — | keep | 11b1 | sample brief text in a fixture; QA names are its content |
| `loomwright/scripts/fixtures/pr-body-evidence/brief-pr-description.md` | — | keep | 11b1 | sample brief text in a fixture; QA names are its content |
| `loomwright/scripts/guard-test-integrity.sh` | `playwright.config` | keep | 11b1 | generic test-runner config detection, not the QA system |
| `loomwright/scripts/propose-common.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/run-ground-truth.sh` | `qa_executor_dispatch_deferred_m2b_1b` | keep | 11b1 | the deferred `qa-executor` branch: records DEFERRED, spawns nothing; kept until Phase 3 item 09 or D18 |
| `loomwright/scripts/test-automate-dismissed.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/test-automate-helpers.d/13-plan-waves.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/test-automate-helpers.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/test-check-qa-removal-manifest.sh` | — | keep | 11b1 | the checker's self-test; its fixtures name QA terms on purpose |
| `loomwright/scripts/test-classify-bot-review.sh` | — | keep | 11b1 | recorded bot-review PR body used as test input (fixture data) |
| `loomwright/scripts/test-classify-risk.sh` | `.agent/verify.json` | keep | 11b1 | 12 keeps a negative test: an edit to the old path alone is no longer high-risk |
| `loomwright/scripts/test-exec-acceptance-hash.sh` | `qa-executor:` | keep | 11b1 | pins the kept `qa-executor:` kind; kept until Phase 3 item 09 or D18 |
| `loomwright/scripts/test-hermetic-egress.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/test-propose-common.sh` | `propose-from-verify.sh` | keep | 11b1 | names the `/propose` verify basis, which 12 re-points in place (the script name stays) |
| `loomwright/scripts/test-rule-conformance-seam.sh` | `qa-executor:` | keep | 11b1 | pins the kept `qa-executor:` prefix in a classifier sentence; kept until Phase 3 item 09 or D18 |
| `loomwright/scripts/test-run-ground-truth.sh` | `qa-executor:` | keep | 11b1 | pins the deferred `qa-executor` branch; kept until Phase 3 item 09 or D18 |
| `loomwright/scripts/test-send-telemetry-core.sh` | `QA_RESULT` | keep | 11b1 | `no_qa_schema_scored` negative pin feeds the removed name to the core; 12 keeps it |
| `loomwright/scripts/test-verify-provides.sh` | — | keep | 11b1 | self-test of the `outputs_verified` gate; not QA |
| `loomwright/scripts/verify-provides.sh` | — | keep | 11b1 | the `outputs_verified` gate; not QA, only its name starts with `verify` (plan section 6, Phase 4) |
| `loomwright/skills/quality-checklist/` | — | keep | 11b1 | general review checklist, not QA (plan section 6, Phase 4) |
| `loomwright/skills/self-heal-advisory/completion-tail.md` | `qa-executor:` | keep | 11b1 | documents the deferred `qa-executor:` checks; kept until Phase 3 item 09 or D18 |
| `loomwright/skills/supervisor-readiness/SKILL.md` | `qa-executor:` | keep | 11b1 | documents the kept `qa-executor:` kind; kept until Phase 3 item 09 or D18 |
| `loomwright/skills/unit-testing/` | — | keep | 11b1 | general testing skill, not QA (plan section 6, Phase 4) |

## Rollback

The tag **`pre-qa-removal`** marks the last commit on `origin/main` with the QA system in it. It is
created as 11b1's first step (not by this item), on the commit 11b1's branch starts from.

To bring the QA system back, restore each `delete` path above from the tag
(`git checkout pre-qa-removal -- <path>`), then re-add by hand what the deletions edited elsewhere:

- **Agents, commands, skills:** the `qa-executor` and `qa-strategist` agents and commands, the `verify`
  command, the QA skill dirs (the `delete` rows under `loomwright/skills/`) and their
  `loomwright/skills/SKILLS_INDEX.md` rows.
- **`loomwright/hooks/hooks.json`:** both SubagentStop matchers (`loomwright:qa-executor`, which runs
  `validate-qa-result.py`, and `loomwright:qa-strategist`).
- **Token budgets:** the `.agents`, `.commands` and `.skills` entries in
  `loomwright/docs/prompt-token-budgets.json` and their mirror rows in
  `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets"; the restored prompts' entries in
  `loomwright/docs/prompt-history-refs-baseline.json` and their allowances in
  `loomwright/docs/vendor-coupling-manifest.json`.
- **CI:** the Playwright pin and cache steps in `.github/workflows/ci.yml` (with
  `read-playwright-pin.sh`). The deleted QA test suites (the `delete` rows for
  `loomwright/scripts/test-*.sh`) come back at their own paths; `scripts/ci-local.sh` runs that
  directory's `test-*.sh` by glob, so it needs no entry.
- **Agent memory:** the tracked dir `.claude/agent-memory/loomwright-loomwright-qa-executor/`.
- **Counts:** the agent, command and skill counts in both manifest descriptions, the CLAUDE.md
  agent-roles heading and table, and README — run `bash scripts/check-doc-currency.sh` to find each.
- **Generated and schema files:** regenerate `loomwright/capabilities.json` with
  `loomwright/scripts/build-capabilities.sh`; restore the QA and verify sections of
  `loomwright/docs/RESULT_SCHEMAS.md`.
- **Re-pointed surfaces:** the `re-point` rows above list every file 11b1, 11b2 and 12 edited in
  place; restore each from the tag where the QA behaviour is wanted back.

## How this list was generated

On 2026-11-18, at commit `a9aa71d` (base `a1b2ee5` plus this item's checker), over **tracked files only,
outside `selvedge/`** — `git ls-files`, never `find`, which would also see gitignored dirs. The QA names
searched for, one per line in `names.txt`:

```text
qa-executor
qa-strategist
qa_executor
qa_strategist
QA Executor
QA Strategist
playwright-e2e
qa-gates
qa-orchestration
qa-strategy
qa-test-patterns
verify-walkthrough
commands/verify.md
agent-help/qa.md
QA_SYSTEM_BLUEPRINT
verify-run.sh
verify-env.sh
verify-helpers.sh
read-verify.sh
verify-fixture-app.py
propose-verify.sh
propose-from-verify.sh
.agent/verify.json
VERIFY_EVIDENCE
VERIFY_ENV
VERIFY_RESULT
VERIFY_QUEUE
QA_RESULT
QA_SESSION
GATE_VERDICT
STRATEGIST_VERDICT
GRAPHQL_RISK_OVERRIDES
MISSING_FUNCTIONALITY_REPORT
validate-qa-result.py
validate-verify-evidence.py
read-playwright-pin.sh
LOOMWRIGHT_VERIFY
qa-failed
.qa-summary
.qa-session
```

The search, the union of three passes (content by fixed name, content by pattern — Playwright, the
`/verify` command, `/loomwright:verify` — and path names):

```bash
{ git ls-files -z | grep -zv '^selvedge/' | xargs -0 grep -l -F -f names.txt
  git ls-files -z | grep -zv '^selvedge/' \
    | xargs -0 grep -l -E -i 'playwright|(^|[^a-z:-])/verify([^a-z-]|$)|loomwright:verify([^a-z-]|$)'
  git ls-files | grep -v '^selvedge/' | grep -i -E 'qa|verify|playwright' | grep -v 'verify-provides'
} 2>/dev/null | sort -u
```

Every file it lists has at least one row, or sits under a deleted directory row. Then, per file:

- **Delete:** the QA files themselves, assigned per the sibling requirements' scopes
  (`qa-split/11b1-*`, `11b2-*`, `12-*`). Two additions to 11b2's list: `propose-verify.sh` (it cannot run
  without `read-verify.sh`) and the QA schema docs the search found beyond the obvious ones
  (`gate-verdict.md`, `graphql-risk-overrides.md`, `missing-functionality-report.md`). The `/agent-help`
  QA page and the QA telemetry fixtures go in 12, with the surfaces that read them.
- **Re-point:** one row per QA name the file contains (a fixed-string match, the same test the checker
  runs). The command `/verify` gets a row only where the file does not also name `verify-provides.sh`
  through a `/` (that file is not QA and stays); where it does, the backticked form is the reference.
  Likewise, where a file also carries the kept `qa-executor` kind, the reference is narrowed to text
  outside that kind, and the kind gets a keep row.
  Map-shaped files (`vendor-coupling-manifest.json`, `prompt-history-refs-baseline.json`) are referenced
  by the exact path key of each deleted file instead.
- **Derived names (the name maps):** the notify, webhook, telemetry, provider-routing, token-ledger,
  result-block-parser, capabilities and contract-parity maps were read by hand, not only grepped. The
  provider-routing seat key `qa_strategist` (in `resolve-routing.sh` and the provider adapter's
  `lens-roles.sh`) is spelled with an underscore, so the literal agent name never finds it; it has its own
  rows.
- **Keep:** written down so no removal PR deletes them by accident.
- **Not rowed:** pending `changelog.d/` fragments (this item's included). They are transient: the version
  bump folds them into `CHANGELOG.md`, a keep row, and deletes them, so a row for one would fail later.
