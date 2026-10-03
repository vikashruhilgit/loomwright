# 13 — Drain bounding: enforce the ceiling, and stop on a severity floor (D4 follow-up)

> **AC7 correction (2026-08-04, drain-bounding-earned-checks).** Launch Pad Phase 2.5 falsified this
> file's "two enforcement regimes" premise: `max_rounds` was always the SAME prose-only bound in the
> shared `skills/review-heal/SKILL.md` §U4 loop body that BOTH the inline `/automate` drain and the
> `review-pr-runner` path read — item 04 stopping at 5 and PR #122 running to 7 is that one bound
> obeyed once and not the other, not two independent regimes. AC2 and rubric bullet 2 below are
> corrected in place to the D2 framing (mechanize the ONE shared bound; do not add a second,
> inline-only counter, which would encode an asymmetry that was never real). Full provenance: the
> `2026-08-04-drain-bounding-earned-checks` Supervisor job brief §"Provenance and the two corrected
> premises" (`.supervisor/jobs/`, filed under whichever of `pending/`/`in-progress/`/`done/` the job
> lifecycle has moved it to).

**Provenance.** Not a new step in the execution order. This is a **defect follow-up to step 4
(Fix 7 / D4), which `FINAL_STATE_GOAL.md` marks SHIPPED in v15.18.0.** D4 states checks must be
*"earned, never repeated by default"*; the root-cause paragraph prescribes *"counter-pressure and
thresholds, not deletion — keep isolation/review/validation as insurance that activates above a
stated bound; default to the cheap path below it."* Both scope items below are that bound failing
to actually bind. No D-decision is renumbered or re-litigated, and no execution-order deviation is
required — this is maintenance on shipped work.

**Evidence (PR #122, 2026-08-03).** The CLAUDE.md-diet PR ran **7 drain rounds** against a corpus
recent-half mean of **3.03** — the worst in the visible window — and `review-heal`'s own
`max_rounds` **hard ceiling is 5**. Rounds 5, 6 and 7 returned, in order: a stale PR *title*, a
hardcoded `3` in a header note, and a pre-existing "four vs six" miscount. Round 7 found nothing at
all. Ledger line: `.supervisor/postmortem/results.jsonl`, `number: 122`, `review_rounds: 7`,
`source: automate_drain`.

## Problem

### 1. The `max_rounds` ceiling is unenforced on the inline-drain path

`skills/review-heal/SKILL.md` declares `max_rounds = 5` a **HARD ceiling** (`:34`, `:365`). That
bound is enforced inside the `review-pr-runner` agent path. But `/automate` §7 requires the engine
to **own exactly ONE inline `/review-pr --until-mergeable` drain** on the main thread — and on that
path *the main thread is the drain*, so nothing enforces the ceiling. It degrades to honour-system.

Verified asymmetry: final-state item 04's run hit the ceiling correctly at 5 rounds **because it
went through the runner**; PR #122 ran 7 **because the engine owned the drain inline**. Same
declared bound, two enforcement regimes, and the unenforced one is the DEFAULT path for `/automate`.

### 2. The drain terminates on zero findings, not on a severity floor

Terminal `READY` requires "no unresolved validated bot findings" — i.e. the loop runs until a round
returns **nothing**. There is no severity floor, so a round that surfaces only LOW/cosmetic items
buys another full review cycle at full price. On PR #122 that bought three extra rounds for a PR
title, a redundant integer, and a pre-existing miscount — none of which blocked merge, and the
required check (`ci`) had been green since round 1.

This is the "repeated by default" behaviour D4 exists to eliminate, surviving in the one loop that
runs on every single item.

## Goal

The declared drain bound binds on **every** path, and the drain stops when nothing material remains
— not when nothing at all remains.

## Scope

1. **Enforce `max_rounds` on the inline-drain path.** `/automate`'s owned drain must count its own
   rounds against the same declared ceiling and terminate at it, recording the terminal state
   exactly as the runner path does (`owned_drain_result`, plus the bound-hit reason). Either the
   engine tracks and enforces it, or `/automate` must refuse to own a drain it cannot bound — pick
   one and state which in the contract. Fail **closed**: an unreadable/absent round count parks
   rather than looping.
2. **Add a severity floor to drain termination.** Terminal `READY` becomes "required checks green
   AND no unresolved validated finding **at or above the floor**", floor default **MEDIUM**,
   overridable by flag. Sub-floor findings are **reported, not dropped** — surfaced in the terminal
   summary and left for the human, never silently discarded. Note the existing category-based
   cosmetic-defer rule from the review-rigor work (`review-rigor-drain-discipline-brief`): a
   category filter is NOT a severity floor; this adds the floor those notes deliberately left out,
   so reconcile the two rather than duplicating them.
3. **Keep both bounds visible in the run record** so a future postmortem can tell a bound-hit
   termination from a clean one — `review_rounds` alone cannot currently distinguish "converged at
   3" from "guillotined at 5".

## Non-goals

- No change to what the drain *reviews*, to the Earned Fallback Review's evidence gate, or to the
  two-lens contract itself (D4 as amended stands).
- **No new CI gate surface.** Explicitly declines the derivation-lint idea considered alongside this
  item: `FINAL_STATE_GOAL.md` §"Deliberately NOT doing" already rejects *"generating the 6 CI-gate
  surfaces from one source"* on cost, and `AGENT_GUIDELINES.md` §"Claim Duplication Rule" makes a
  gate the LAST resort. Recorded here as considered-and-declined so it is not re-proposed.
- Nothing merges automatically; the never-merge invariant is untouched.

## Acceptance criteria

- [x] Given `/automate` owning an inline drain, when round count reaches the declared ceiling, then the drain terminates with a bound-hit terminal state and does NOT start another round — verified by a test that drives the inline path past the ceiling. (`loomwright/scripts/test-drain-rounds.sh` §B.)
- [x] **AC2 (REWRITTEN per D2 — supersedes the original wording above).** Given that `/automate`'s inline drain and the `review-pr-runner` path execute the *same* `skills/review-heal/SKILL.md` §U4 loop body, when either runs, then the declared bound is enforced by the **same mechanized counter** (`loomwright/scripts/drain-rounds.sh`) on that shared path, and neither path carries a private bound of its own. (The original wording asserted an inline-vs-runner asymmetry that Launch Pad Phase 2.5 verified never existed — see the correction note at the top of this file.)
- [x] Given a drain round whose only findings are below the severity floor, when the round completes, then the drain terminates `READY` without another cycle, and those findings appear in the terminal summary rather than being dropped. (Implemented as reading B — fixed-then-stop, `sub_floor_fixed[]` — not reading A/find-then-defer; see the job brief's "PINNED SEMANTICS".)
- [x] Given a finding at or above the floor, when the round completes, then the drain continues exactly as today (no regression in healing real issues).
- [x] Given an unreadable round count or severity, when the gate evaluates, then it fails CLOSED (parks) rather than looping or silently passing. (`test-drain-rounds.sh` §C; `automate-helpers.sh gate-eval` condition 1b.)
- [x] Given a completed drain, when the run record is read, then a bound-hit termination is distinguishable from a converged one. (`REVIEW_HEAL_RESULT.termination_reason`, also distinguishes `sub_floor_converged`.)

## Outcomes Rubric

- `max_rounds` enforced by a mechanized counter on the shared §U4 drain path (both entry paths), with a test that drives it past the ceiling
- The bound binds on the single loop body both entry paths share — no private per-path counter is introduced (D2 correction — supersedes the original "inline and runner paths terminate at the same declared bound" framing, which implied two counters coincidentally agreeing rather than one shared counter)
- Severity floor implemented at termination time only — sub-floor findings are fixed, then not re-scanned (never declined a fix), and reported via `sub_floor_fixed[]`
- Fail-closed on unreadable round count or severity
- Bound-hit vs converged vs sub-floor-converged termination distinguishable in the run record
- No new CI gate surface added

## Status: done

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent
