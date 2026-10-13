# validation-gate: a Validation section the parser cannot read must fail closed

## Status: proposed

> Propose-only follow-up from run `automate-2026-10-12-181635` (af36-remainder/01, PR #502). Not enqueued.
> Extends the engine-owned summary draft
> `automate-2026-10-12-181635-L1--01-validation-unrun-gate-f08e04--dismissed-summary.md` (owner: follow-up) with
> reproduced evidence. Its LOW rating understates entry 2.

## Problem (reproduced 2026-10-13 against main 0b65a93, `_lanes_validation_rows` in `scripts/automate-lanes.sh`)
1. **Fail-open on list style.** The entry grammar reads only `1. ` and `- ` items. A `## Validation` section written
   with `* ` bullets or `1) ` numbering yields ZERO entries; `validation-gate` then answers
   `none — no running-system step` and the item parks READY, so an unrun running-system step passes the blocking gate.
2. **Over-block on prose.** Not-run vocabulary is matched as a substring: a running-system step with pasted output reads
   PASS, but adding "the machine was not running hot" to its line flips it to NOT-RUN. Fails closed (a wrong park the
   owner overrules), so lower priority.
3. (Not reproduced, informational) `--check` label extraction is ambiguous when a title contains `: `.

Exposure today: 0 of the 65 requirements with a Validation section use `* ` or `1) `, so (1) has not fired yet.

## Scope
1. Fail closed: a `## Validation` section that exists but parses to zero entries ⇒ `validation-gate` prints `unrun`
   (names the reason), never `none`. Optionally also accept `* ` and `N) ` items.
2. Match not-run vocabulary as phrases at word boundaries (`not run`, `not verified`, `skipped` as a status), not as
   substrings of longer words.
3. Tests: one leg per list style (proves (1) is closed, red when the guard is removed); the "not running hot" leg
   reads PASS; existing legs unchanged.
