# 03 — SDK-runner token levers (effort / task_budget / context editing) + eval metric

> Motivation: prompt-orchestrated agents cannot touch API-level cost controls; the
> quarantined `loomwright/sdk-spike/` runner (v15.8.0, opt-in `--sdk-runner`, default
> OFF) can. The tokenizer inflation raises the payoff of the spike: if arm 3 of the
> pre-registered FABLE_PARITY_EVAL wins on defects AND tokens, its GO condition
> strengthens. This job adds the levers and the measurement, WITHOUT changing the
> quarantine posture or any default path.

## Goal
The SDK runner supports per-role `effort`, an opt-in per-subtask `task_budget`, and
context editing for long poll loops; token cost per subtask is a first-class recorded
metric in the spike record and the parity eval.

## Evidence
- `loomwright/sdk-spike/` — TypeScript port of Execute Manager Phase 3 via
  `@anthropic-ai/claude-agent-sdk` (pinned ^0.3.202, committed lockfile), offline
  --dry-run + self-test (25/25). Read the actual runner source for current query() call
  shapes before asserting anything (memory: verify invocation shapes from the file).
- Claude Agent SDK is a distinct surface from the raw Messages API — verify which of
  effort / task budgets / context-editing knobs the pinned SDK version actually exposes
  (check the SDK's own docs/types first; if a knob is not exposed, record that in the
  capability matrix as a gap rather than hacking around it).
- Pre-registered eval: `docs/SPIKES/FABLE_PARITY_EVAL.md` already caps arm-3 token cost
  at 1.5× arm-2. Pre-registration discipline: metric/decision-rule changes must be made
  BEFORE any eval run and be visible as a standalone reviewed amendment.

## Scope
1. **Runner config** (`sdk-spike/`): per-role effort mapping — **locked defaults:**
   worker `medium` for mechanical subtasks; reviewer higher (exact reviewer value in
   the config table, not hard-coded inline). Table lives in runner config; overrides
   remain config-driven. Opt-in `task_budget` per worker query (respect the documented
   20k minimum; omit entirely when unset), and context editing / history pruning for
   the wave loop where the SDK exposes it. Fail-closed on invalid config values.
2. **Per-subtask token accounting**: capture usage from each query() result; emit into
   the runner's EXECUTE_RESULT-equivalent output (additive fields) and the --dry-run
   fixtures.
3. **`docs/SPIKES/SDK_RUNNER_SPIKE.md`**: extend the capability/parity matrices with the
   three levers (supported / not-exposed-by-SDK / deferred, doc-verified) and the
   token-per-subtask metric.
4. **`docs/SPIKES/FABLE_PARITY_EVAL.md` amendment**: add token-cost-per-subtask as a
   recorded (not decision-changing) metric; the existing 1.5× decision rule stays
   UNCHANGED — pre-registration is only amended additively, with an explicit "amended
   before any run" datestamp.
5. Extend the runner self-test to cover config parsing + accounting fields (offline).

## Constraints / invariants
- Quarantine posture unchanged: `sdk-spike/` stays UNCOUNTED, referenced only by the
  opt-in `--sdk-runner` seam, absent from manifests; `dist/` stays gitignored; the
  default path stays byte-identical with the flag off.
- Fail CLOSED on runner unavailability (`sdk_runner_unavailable`) — unchanged.
- No change to gate shapes, heal decisions, or the never-merge invariants.
- Counts UNCHANGED (14/21/41/22). Minor version bump + CHANGELOG; description version
  string in place.
- If a lever is not exposed by the pinned SDK version, do NOT upgrade the pin in this
  job without recording the diff of SDK versions in the spike doc; prefer documenting
  the gap.

## Acceptance criteria
- [ ] --dry-run + self-test pass offline with the new config surface (count updated
      honestly from 25/25 to the new N/N).
- [ ] Config table encodes worker effort default `medium` and a higher reviewer value;
      invalid values fail closed.
- [ ] Per-subtask token fields appear in the runner output on dry-run fixtures.
- [ ] Capability matrix rows for effort / task_budget / context editing are doc-verified
      (link to SDK docs/types), with honest not-exposed entries where applicable.
- [ ] FABLE_PARITY_EVAL amendment is additive, datestamped, and does not alter the
      decision rule.
- [ ] Default path byte-identical with `--sdk-runner` off (diff proof in PR).

## Test plan
`sdk-spike` self-test + --dry-run offline. No live API calls required; if a live smoke
run is performed, paste real usage numbers, else state live verification pending.

## Out of scope
Graduating the runner (eval-gated per the spike's GO/NO-GO), running the eval itself,
prompt-cache breakpoints inside the runner (candidate follow-up), main-path changes.

## Status: done
- completed 2026-07-19 via /automate (PR #102, rubric 7/7, heal PASS)
