# Loomwright's surfaces that named the old QA now point at Selvedge, and a test stops the old names coming back

## Status: pending

> Phase 4, item 12 of the approved plan `qa-split/00-plan.md` (rev 2, owner-approved 2026-11-12).
> Decisions: D1, D4 (Loomwright reads Selvedge's CLI and one JSON file, never imports it), D15b (W4:
> selvedge owns `selvedge.json`). Works strictly from 11a's manifest `re-point` rows.

## Why

After 11b (both parts), files that routed to, counted or read the old QA still name it: `agent-help`, `dreaming`
(`--agent qa-executor`), the notify / webhook / telemetry / routing / token-ledger name maps,
`classify-risk.sh`'s trusted paths (`.agent/verify.json`), `/propose --from-verify` (reads `/verify`'s
`evidence.jsonl`), setup, handoff, rules and docs. Left alone they either do nothing or point at files
that no longer exist.

## Story

**As** the plugin's maintainer,
**I want** every manifest `re-point` row changed to its new target, each with a test,
**so that** no surface silently reads a file nothing writes any more, and the old names can't creep back.

## Scope

- Every manifest `re-point` row, including at least:
  - `classify-risk.sh`: `.agent/verify.json` in the trusted root-only paths becomes `selvedge.json`
    (a PR that edits it is high-risk, as `.agent/verify.json` was).
  - `/propose --from-verify` (`propose-from-verify.sh` and the command text): reads Selvedge's
    `verdict.json` from a run folder, one candidate per FAIL criterion, each citing the criterion, the
    expected value, the step that failed and the plan hash. Writes only under
    `.supervisor/requirements/proposed/`, as today; never queues.
  - The name maps (notify, webhook, telemetry, provider routing, token ledger), `agent-help`,
    `dreaming`, setup, handoff, rules and docs: drop the QA names.
- Each re-pointed surface gets a test that fails if the old name or path comes back.

## Acceptance criteria

- Given this branch, when `check-qa-removal-manifest.sh --expect 12` runs, then it exits 0.
- Given a PR diff that edits `selvedge.json`, when `classify-risk.sh` runs, then the diff is high-risk;
  given one that edits `.agent/verify.json`, then that path alone no longer makes it high-risk.
- Given a Selvedge run folder whose `verdict.json` has 1 FAIL and 2 PASS, when
  `/propose --from-verify <run_dir>` runs, then exactly one candidate file is written under
  `.supervisor/requirements/proposed/`, citing that criterion; given a malformed or missing
  `verdict.json`, then it writes nothing and says why (exit non-zero), never an empty proposal.
- Given `dreaming`'s agent list or any name map, then `qa-executor` and `qa-strategist` do not appear,
  and a test pins that.
- Loomwright still imports nothing from `selvedge/` (D4): it reads `verdict.json` as data only.

## Non-goals

- The `verify:` Executable Acceptance kind and removing the `qa-executor` arm (Phase 3, item 09).
- Calling the `selvedge` CLI from Loomwright (item 09).
- Changes inside `selvedge/`.

## Owner decisions

- 2026-11-12: plan rev 2 approved, including item 12's list and the `selvedge.json` trusted-path swap
  (W4).
- 2026-11-18: start Phase 4 now (this session).

## Priority: MVP

**Rationale:** Without it, `/propose --from-verify` reads a file nothing writes and the risk classifier
guards the wrong config file.

## Assumptions

- `verdict.json`'s shape is the one Selvedge 0.7.0 writes (Phase 1, item 04); the parser reads only its
  documented fields and refuses an unknown `schema_version`.

## Risks

- `verdict.json` changes shape in a later Selvedge release. Mitigation: refuse an unknown
  `schema_version` with a named reason, pinned by a test.

## Validation (must pass before merge)

1. **Static — manifest:** `bash loomwright/scripts/check-qa-removal-manifest.sh --expect 12` exits 0.
2. **Static — tests:** the `/propose --from-verify` and `classify-risk.sh` tests cover the cases in the
   acceptance criteria; `bash scripts/ci-local.sh --affected` passes, then CI `ci` is green.

## Depends on

11b2-remove-qa-scripts-schemas-ci.md

## Touches

loomwright/scripts/classify-risk.sh
loomwright/scripts/test-classify-risk.sh
loomwright/scripts/propose-from-verify.sh
loomwright/scripts/propose-verify.sh
loomwright/scripts/propose-common.sh
loomwright/scripts/test-propose-from-verify.sh
loomwright/commands/propose.md
loomwright/commands/agent-help.md
loomwright/scripts/emit-token-ledger.sh
loomwright/scripts/notify-desktop.sh
loomwright/scripts/send-webhook.sh
loomwright/scripts/send-telemetry-core.sh
loomwright/scripts/resolve-routing.sh
loomwright/scripts/build-capabilities.sh
loomwright/scripts/result_block_parser.py
loomwright/skills/workflow-management/SKILL.md
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/skills/self-heal-advisory/completion-tail.md
loomwright/agents/launch-pad.md
loomwright/agents/plan-reviewer.md
changelog.d
