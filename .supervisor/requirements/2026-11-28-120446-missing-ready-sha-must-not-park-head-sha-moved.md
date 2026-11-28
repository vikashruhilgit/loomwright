# A drain report without ready_sha must not park head_sha_moved

## Status: pending

**Story: A drain report without ready_sha must not park head_sha_moved** (type: story)

**As an** owner (or a coordinator session) running `/automate` with an item that drained `READY`,
**I want** a READY drain report that does not carry `ready_sha` to be refused with a clear error naming the field, or parked under its own name,
**so that** I never go looking for a head move that never happened, and an optional field never changes the gate's verdict.

Source: GitHub issue https://github.com/vikashruhilgit/loomwright/issues/1006. Seen on PR https://github.com/vikashruhilgit/loomwright/pull/995 (run automate-2026-11-27-162041) and PR https://github.com/vikashruhilgit/loomwright/pull/1004 (run automate-2026-11-28-081337) on 2026-11-28, Loomwright 18.1.2. Head 3d9e48a on #1004 was unchanged and every check was green, but the gate parked `head_sha_moved`. It parks nearly every drained PR, because the coordinator's DRAIN report usually omits the field.

## Problem

`ready_sha` is optional in the DRAIN report and the drain report (`docs/result-schemas/automate-run.md`, the DRAIN report and Drain report bullets), but `gate-eval` condition 2 needs it. When the field is absent:

1. `automate-next-step.sh`'s DRAIN check (`ns_check_drain_report`) checks `ready_sha` only when it is present, so the report is accepted.
2. `drain-result` writes no `- ready_sha:` line (the documented "a READY report with no ready_sha writes no line"), and the GATE report built after `learning-emit` copies `ready_sha` only when the DRAIN report had it.
3. `ns_gate_eval` always writes the ctx key, `--arg rs "$(st ready_sha)"`, so the ctx carries `"ready_sha": ""`.
4. `automate-helpers.sh` `gate_eval` condition 2 reads it with `J '.ready_sha'` (`.ready_sha // "__MISSING__"`). jq's `//` replaces only null/false, so `""` stays `""`. The `""` != live head test then prints `PARK: head_sha_moved`. A truly absent key reads `__MISSING__` and also prints `head_sha_moved`.

So "the drain never told us its READY head" and "the head moved after READY" give the same park reason. `--merge-parked`'s `merge-guard` already tells them apart (`ready_sha_missing`); the gate on the live `/automate` tail does not.

The issue's description, that the gate compared against the drain's start commit (64e794d), describes what the owner saw. The code does not read the start `head_sha` for condition 2 at all. It compares an empty string, and that never equals any head.

## Evidence — reproduced 2026-11-28 on 1887fca (Loomwright 18.1.2 tree)

Scratch fixture only: no run file, no split test part run on its own. `gate-eval` ran directly with a stub `gh` (`LOOMWRIGHT_GH_BIN`) whose `pr view` returns `headRefOid 3d9e48a…aa`, `baseRefName main`, `reviewDecision APPROVED`, plus a REVIEW_HEAL_RESULT sidecar `decision: READY`, `termination_reason: converged`. Three ctx files, identical except for `ready_sha`:

| ctx `ready_sha` | gate-eval output |
|---|---|
| key absent | `PARK: head_sha_moved` |
| `""` (what `ns_gate_eval` writes when the report omitted it) | `PARK: head_sha_moved` |
| equal to the live head | `PARK: unresolved_human_thread` (passes condition 2; the stub has no GraphQL, so condition 3 parks) |

Command shape: `LOOMWRIGHT_GH_BIN=<stub> bash loomwright/scripts/automate-helpers.sh gate-eval <any PR URL; the stub ignores it> <ctx.json> --root <scratch>`.

## Goal

A missing `ready_sha` is never reported as `head_sha_moved`. The READY head must be stated by the drain, and when it is not, the run says so by name.

## Scope

1. **Refuse at write time.** A DRAIN report (the owned drain or the fix-now re-drain) whose REVIEW_HEAL_RESULT `decision` is `READY` and that carries no `ready_sha` exits 2, names the field (e.g. `--result: a READY DRAIN report must carry ready_sha (the PR head the drain ended READY on) — nothing written`), and writes nothing. The same goes for a READY legacy drain report (`drain_result: READY`). ESCALATED and `no_terminal_block` reports are unchanged.
2. **Name it at the gate (defense in depth).** `gate-eval` condition 2 treats an absent, null or empty `ready_sha` as `PARK: ready_sha_missing`, a new reason distinct from `head_sha_moved`, which stays for a real mismatch with the live head. Fail closed: it still never merges.
3. **Contract docs say it.** `ready_sha` is documented as required on a READY DRAIN / drain report, and `ready_sha_missing` is added to the gate's PARK reasons. Every surface that restates the report fields or the gate's reasons is updated in the same change.
4. **The spawn/then text already asks for `ready_sha`.** Keep it, and make the refusal message point at the same wording so a coordinator can fix its report and re-send it.

## Non-goals

- Substituting the live head (or the drain's start `head_sha`) for a missing `ready_sha`. That would make condition 2 true by construction and drop its only job, which is to catch a push after READY. `merge-guard` already refuses to do this ("the live head is never substituted").
- Reading the head from REVIEW_HEAL_RESULT. The schema carries no READY-head field (`escalation_sha` is ESCALATED-only), and `sidecar-check` refuses `ready_sha` as a non-schema key. Adding one is a REVIEW_HEAL_RESULT schema change, out of scope here.
- Changing `--merge-parked`'s `merge-guard` (it already parks `ready_sha_missing`).
- Any change to which conditions `gate-eval` checks or to the one-merge-executor invariant.

## Owner decisions

- Fix shape (from the issue's two options): required `ready_sha` with a clear refusal, plus a named gate park. Chosen in this /product-owner session, 2026-11-28, from the two forms #1006 allowed; the live-head option is rejected (see Non-goals). The owner may still pick the other form at Launch Pad.

## Acceptance criteria

**Happy path:**
- [ ] Given a READY DRAIN report carrying a hex `ready_sha` equal to the live head, when the tail runs to `gate-eval`, then condition 2 passes exactly as today (no new park).
- [ ] Given a READY DRAIN report carrying a `ready_sha` that differs from the live head, when `gate-eval` runs, then it parks `head_sha_moved` as today.

**The defect:**
- [ ] Given a READY DRAIN report (first drain or fix-now re-drain) with no `ready_sha`, when `--result` is sent, then the driver exits 2 with a message naming `ready_sha`, and the run file, `## Current`, `## Progress`, the sidecars and the review-heal sidecar are all byte-unchanged.
- [ ] Given a READY legacy drain report (`drain_result: READY`) with no `ready_sha`, when `--result` is sent, then the same refusal applies.
- [ ] Given a gate ctx whose `ready_sha` is absent, `null` or `""`, and a live head that has not moved, when `gate-eval` runs, then it prints `PARK: ready_sha_missing`, never `PARK: head_sha_moved`, and never merges.

**Edge cases:**
- [ ] Given an ESCALATED DRAIN report or a `no_terminal_block: true` report with no `ready_sha`, when `--result` is sent, then it is accepted as today.
- [ ] Given a malformed `ready_sha` (non-hex, wrong length), when `--result` is sent, then the existing `malformed ready_sha` refusal still fires.
- [ ] Given the replay rule (a re-sent first report carrying `ready_sha` is a replay), when the refusal is added, then the replay tests still pass.

## Validation (must pass before merge)

1. **Static — gate-eval test:** a new case in `loomwright/scripts/test-automate-helpers.sh` (part `05-gate-eval.sh`, through the suite runner, never the part on its own) asserts `PARK: ready_sha_missing` for an absent, null and `""` `ready_sha` with an unchanged stub head, and that `head_sha_moved` still fires on a real mismatch. It fails on today's code (the repro above).
2. **Static — driver test:** a new case in `loomwright/scripts/test-automate-next-step.sh` asserts the exit 2 + byte-unchanged run file for a READY DRAIN report without `ready_sha`, and acceptance for ESCALATED / `no_terminal_block` without it.
3. **Static — CI:** `bash scripts/ci-local.sh --affected` passes locally, and GitHub's required `ci` check passes (doc currency, token budgets, golden fixtures).

## Priority: MVP

**Rationale:** it misreports nearly every drained PR's park, sends the owner after a head move that never happened, and blocks `--auto-merge` from ever merging when the coordinator omits the field.

### Assumptions
- Defect evidence: reproduced — `gate-eval` run on 1887fca against a scratch ctx and a stub `gh` (table above): absent and `""` `ready_sha` both print `PARK: head_sha_moved` with the head unchanged.
- The coordinator can always state `ready_sha`: the spawn text already asks for "the PR head the drain ended READY on", and the drain session knows its final pushed head.
- Golden fixtures whose READY drain reports omit `ready_sha` (found by grep: `drain-pinned-start-line-current-not-set`, `drain-owned-drain-started`) will need the field added. That is a test-data update, not a behaviour change; the implementer re-greps for others.

### Dependencies
- Depends on: none.
- Blocks: none named. It makes `--auto-merge` usable on runs where the coordinator omitted the field.

### Risks
- A coordinator prompt that does not pass `ready_sha` now gets a refusal instead of a wrong park. The refusal message must say how to fix and re-send the report, or runs stall at the drain report.
- Doc mirrors: the report-field and PARK-reason lists are restated across several docs (`automate-run.md`, `modes-and-merge-gate.md`, `helpers.md`, `resume.md`, the gate's header comment). Per the house rule, update them in the same change.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-28-120446-missing-ready-sha-must-not-park-head-sha-moved.md"`.

## Depends on
none

## Touches
loomwright/scripts/automate-next-step.sh
loomwright/scripts/automate-helpers.sh
loomwright/scripts/test-automate-next-step.sh
loomwright/scripts/test-automate-next-step.d/03-run-drain.sh
loomwright/scripts/test-automate-helpers.sh
loomwright/scripts/test-automate-helpers.d/05-gate-eval.sh
loomwright/scripts/test-automate-helpers.d/05-gate-eval-harness.sh
loomwright/scripts/fixtures/automate-golden/drain-pinned-start-line-current-not-set/next-step.results
loomwright/scripts/fixtures/automate-golden/drain-owned-drain-started/next-step.results
loomwright/docs/result-schemas/automate-run.md
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/automate-loop/helpers.md
loomwright/skills/automate-loop/run-file.md
loomwright/docs/loop-inventory/automate-loop.md
changelog.d/ready-sha-required.md
