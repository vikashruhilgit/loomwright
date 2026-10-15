# automate-speed/10 — Choose the coordinator's model by A/B measurement (Haiku 5.5 vs Sonnet 5.5)

## Status: pending

## Problem
After items 06–09 the coordinator's job is small: read one JSON instruction, launch a phase, hand back its result,
relay a question. It no longer needs to follow ~1MB of rules, so it may not need the strongest model. Prices per MTok
(Anthropic table, 2026-10-15): Opus 5.5 $4/$20, Sonnet 5.5 $2/$10, Haiku 5.5 $0.10/$0.50 up to a 100K prompt and
$0.50/$2.50 above it. All three have a 1M context; the open question is rule-following reliability, which has never
been measured on this loop. `token-economy/06-model-router-gate.md` (never shipped) proposed routing by task class.

## Goal
<!-- bump: minor -->
An eval suite runs the same Queue items with the coordinator on Haiku 5.5 and on Sonnet 5.5, and the coordinator's
default model is set from the result: the cheaper model wins only if it matches on run-file parity and wrong
questions.

## Scope
- `loomwright/evals/coordinator-model/`: `claude plugin eval` cases that drive the coordinator loop over fixed
  fixture items (scratch repos; no network merges), graded on (1) run file byte-identical to the golden expectation,
  (2) no question asked that the instruction did not carry, no instruction skipped, (3) tokens from item 03's report.
- A coordinator model setting: a `.supervisor/config.json` key read by `automate-next-step.sh`, documented next to the
  driver's instruction schema in `docs/result-schemas/automate-run.md`; no new `/automate` flag and no
  `ARCHITECTURE_CONTRACTS.md` edit (keeps this item off `commands/automate.md`, which item 16 edits in the same wave,
  and off the contract doc item 26's agent edits pull in; item 18 adds the §"Cost Profiles" pointer). Default unchanged until the evidence says otherwise.
- `docs/evidence/coordinator-model-ab.md`: the commands, per-model scores, tokens, and the decision.
- Fold the relevant part of `token-economy/06` (escalate-on-failure valve: ≥3 FAILs in the last 20 ⇒ back to the
  stronger model, one-directional) into the setting; record in the PR body that 06 is superseded for the coordinator.

## Non-goals
- Changing the model of any phase that implements, reviews or writes a brief (D3).
- Auto-demotion of models.

## Owner decisions (from _BACKLOG.md)
- D3: the coordinator model is chosen by measurement, not opinion; judgment phases stay on the strong model.

## Acceptance criteria
- Given the eval suite, when run with each model, then `docs/evidence/coordinator-model-ab.md` records per-case
  parity, wrong-question count and tokens for both models, and the PR body links to it.
- Given the decision, then the default coordinator model equals the cheapest model with 100% parity and 0 wrong
  questions; if none qualifies, the default stays the session model and the evidence says so.
- Given ≥3 coordinator FAILs in the last 20 runs, then the setting escalates to the stronger model and records why.

## Validation (must pass before merge)
1. The eval suite passes once on the chosen model; `test-automate-next-step.sh`; report `<passed>/<total>`.
2. Mutation control: a fixture whose expected run file is wrong ⇒ the parity grader fails.

## Measurements
- Each model: 3 runs of the full suite (variance). Frozen commit: the commit that adds the suite.

## Depends on
09
03

## Touches
loomwright/evals/coordinator-model/
loomwright/scripts/automate-next-step.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/docs/result-schemas/automate-run.md
docs/evidence/coordinator-model-ab.md
changelog.d/as10-coordinator-model-ab.md
