# The run is model-free, the evidence is runner-written, and the verdict is derived from it

## Status: pending

> Phase 1, item 04 of `qa-split/00-plan.md` (rev 2, approved 2026-11-12).
> Decisions: D6 (hash check, no model in the run), D7 (PASS rule, stable wait, exit precedence),
> D9 (`evidence_class`), D10 (no cached assertions), D13 (local redacted evidence). Red-team: C4, F3 (part), C3 (schema side).

## Why

If the model writes the evidence or the summary, the model is the judge. Here the runner process writes
every evidence line, and `verdict` reads only those lines. The run can't drift from the plan because it
refuses a plan whose hash changed.

## Design

- **`selvedge run <run-dir>`:** recompute sha256 of `plan.json`; mismatch with `plan.sha256` → exit 2
  `plan_modified`, nothing runs. A run folder that already has `evidence.jsonl` → exit 2 `already_run`
  (one plan, one run; a new attempt is a new revision, item 03).
- **`selvedge run --replay <frozen-run-dir>`:** the regression path (D6, P9). Creates a new run folder,
  copies `plan.json` from the frozen folder, checks its sha256 against both that folder's `plan.sha256`
  and the `plan_sha256` recorded for that run in `runs.jsonl` (editing plan and hash together still fails), and runs
  it with no model (zero planner tokens). `verdict.json` and `runs.jsonl` record `replay_of: <run-id>`;
  `plan_revision` is unchanged. An approved `seed`/`reset` hook runs first, because expected values often
  depend on data; with none, the verdict says `data_state: unmanaged`. Drift shows as BLOCKED
  `step_failed` (fixed by re-planning: a new revision) or FAIL, never as a repaired step. Frozen
  `plan.json` files contain `{{NAME}}` placeholders only, so a repo may commit them as its regression set. Then for each criterion, in a fresh browser context (item 02 route guard
  installed first; `storageState` from item 05 when present):
  - execute steps via Playwright; `wait_for` and every action use Playwright's auto-wait; before an
    `expect` that would FAIL, wait for network idle + a stable DOM (two equal snapshots 500 ms apart, capped
    by a timeout) and re-read once — FAIL only if the re-read still mismatches (WebTestBench's async-loading
    false FAILs);
  - a locator that matches nothing, or a hidden/covered click target → the criterion ends BLOCKED
    `step_failed` with the step index (not FAIL: the check couldn't be performed);
  - N identical snapshots after actions (stuck screen) → BLOCKED `stuck_screen`;
  - append one JSON line per step to `evidence.jsonl` (step, locator, outcome, value read, duration).
    `{{NAME}}` values are written as `{{NAME}}`, never resolved.
  - No model call anywhere in `run` (enforced by a test that fails if the planner binary is invoked).
- **Evidence files** (gitignored `.selvedge/` — `selvedge env init` adds the ignore line): `evidence.jsonl`,
  one screenshot per criterion end state. **Traces off by default**; with `--trace`, the trace is
  post-processed to drop `Cookie`, `Set-Cookie` and `Authorization` header values and any `{{NAME}}`
  resolved value before it is kept.
- **`selvedge verdict <run-dir>`:** reads `evidence.jsonl` + `plan.json` only. Per criterion:
  `PASS` if the final `expect` held and no material assumption is recorded (else NOT_VERIFIABLE
  `material_assumption`, with the assumption text); `FAIL` if it failed after the stable wait; `BLOCKED` with the named
  reason; `NOT_VERIFIABLE` if no value was read or the criterion was not testable. Writes `verdict.json`
  (`schema_version`, `target`, `plan_sha256`, Playwright version, per criterion: `verdict`, `evidence_class`
  (`structured-read` for web), `read_value`, `matched`, `expected`, `reason`, `interpretation`,
  `unverified_assumptions`, step summary), plus `plan_revision` and `prior_revisions`: the verdict of every
  earlier revision for the same `criteria_sha256`, first one first. `verdict.json` is local; it is not
  the PR comment. Exit precedence:
  any FAIL → 1; else any BLOCKED → 2; else any NOT_VERIFIABLE → 3; else 0.
- **Run log:** append one line to `.selvedge/runs.jsonl`: `ts, entry (session|ci|loomwright via
  SELVEDGE_ENTRY), counts per verdict, planner tokens, duration, plan_sha256, criteria_sha256,
  plan_revision, replay_of`. This is the §8 data source.
- **Budget:** a per-run wall-clock budget and the planner token budget; exceeding either → remaining
  criteria BLOCKED `budget_exceeded`.

## Acceptance criteria (each a test, against a tiny fixture app served on localhost)

- Edit one byte of `plan.json` after `plan` → `run` exits 2 `plan_modified`, no browser launched.
- A criterion whose `read` returns nothing → NOT_VERIFIABLE, never PASS.
- A value that appears 1.5 s after the action → PASS (stable wait), not FAIL.
- A genuinely wrong value → FAIL with `read_value` and `expected` both in `verdict.json`.
- Mixed verdicts {PASS, NOT_VERIFIABLE, BLOCKED} → exit 2; add a FAIL → exit 1; only PASS + NOT_VERIFIABLE → 3.
- `--trace` on a page that sets a cookie → the kept trace contains no cookie value.
- `run` invokes no planner (test shim records zero calls).
- `runs.jsonl` gains exactly one line per run with the fields above.
- `run` on a folder that already ran → exit 2 `already_run`, no browser launched.
- `run --replay` of a PASSed frozen run → a new folder, same `plan_sha256`, `replay_of` set, planner shim
  records zero calls; same app → PASS again.
- `run --replay` after the fixture app renames a button's label → BLOCKED `step_failed` with the step
  index, not PASS and not a changed locator.
- `run --replay` of a folder whose `plan.json` was edited → exit 2 `plan_modified`.
- A criterion that FAILs on revision 1 and PASSes on revision 2 → revision 2's `verdict.json` carries
  `prior_revisions: [{revision: 1, verdict: FAIL}]`.
- A matching value with a `material: true` assumption → NOT_VERIFIABLE `material_assumption`, never PASS.
- A `negative` criterion whose side-effect count goes from 0 to 1 → FAIL.

## Depends on

03

## Touches

- `selvedge/lib/runner/**`, `selvedge/lib/verdict*`, `selvedge/schemas/verdict.schema.json`
- `selvedge/tests/**`, `selvedge/tests/fixture-app/**`
