# 07 — One `DECISIONS.md`: the decision layer, with spike docs demoted to evidence

## Problem
Establishing what the project has already decided takes several turns of reading, and the reasoning
is scattered across files that no longer agree about their own currency.

Measured 2026-08-06:
- **10,728 lines** of docs across `loomwright/docs/` + `SPIKES/`.
- **18 spike docs**, **10 of them frozen at a single 2026-07-02 commit**.
- Answering one question — *"do we keep the code graph?"* — required reading **six sources**:
  `NORTH_STAR_DIRECTION.md` (the decision), `CODE_GRAPH_OWNERSHIP.md` (the evidence),
  `LOCAL_TWIN_PATH.md` (the gate result), `FINAL_STATE_GOAL.md` (the current homing), plus two
  requirement files. Decision, evidence, result, and status each lived somewhere different.

The failure mode is specific and worth naming precisely: **there is no decision layer.** There is an
evidence layer (spikes), a contract layer (`ARCHITECTURE_CONTRACTS`, `RESULT_SCHEMAS`), and a goal
layer (`FINAL_STATE_GOAL`) — but *"what did we decide, when, why, and is it still live"* has no
single home, so each decision is reconstructed from its evidence every time.

**Scope honesty:** this does not prevent every stale-context error. A reader who asserts from a gap
in one table instead of checking the source will still be wrong. What it removes is the six-source
hunt — a smaller, real, and separately worthwhile win. Do not oversell it in the doc itself.

## Goal
One `DECISIONS.md` that is the single home for every decision, with spike docs explicitly demoted to
the evidence they contain and status-banner-marked.

## Scope

1. **Create `loomwright/docs/DECISIONS.md`.** One row per decision:
   `id · decision (one line) · why (one line) · date · evidence pointer · status (live | superseded-by-<id> | void)`.
   Superseded rows are **kept, never deleted** — the audit trail is the point. Existing decision
   identifiers (`FINAL_STATE_GOAL`'s D1–D11) are absorbed with their IDs preserved, not renumbered.

2. **Harvest from what exists** — `FINAL_STATE_GOAL.md` (D1–D11), `NORTH_STAR_DIRECTION.md` (six bets
   + the explicit NOs), `CODE_GRAPH_OWNERSHIP.md` (reposcan PARKED; graphify complementary),
   `LOCAL_TWIN_PATH.md` (step gates), `EVAL_FINDINGS_AND_FIXES.md` (4d REJECTED, 4f actual target),
   and this queue's own outcomes (D9 split, graph retired). Where two docs disagree, **record the
   conflict rather than silently picking a winner** — an unnoticed contradiction is what this item is
   fixing.

3. **Status-banner every spike doc** — live / superseded / historical, with a pointer to its decision
   row. Do not delete or trim them: `CODE_GRAPH_OWNERSHIP.md` intentionally retains *retracted* claims
   with ⚠️ corrections, and that record is what allowed an unfair benchmark to be identified as
   unfair later. Evidence is preserved; only its status is clarified.

4. **Apply the Claim Duplication Rule to decisions.** The rule already in `.agent/rules/process.json`
   says a claim lives in exactly one authoritative place and every other surface derives or links.
   Extend it to decisions: recorded once in `DECISIONS.md`, linked everywhere else. Note that this
   rule was violated six times in its own introducing PR — including by its own `.agent/rules` copy,
   which hardcoded a count — so this item must be checked against itself before it ships.

5. **Add a currency check.** Extend `check-doc-currency.sh` (or add a sibling) to verify: every
   `DECISIONS.md` row has a resolvable evidence pointer, and every spike doc carries a status banner
   naming a row that exists. Both directions, red on a seeded violation. Without this the new doc
   rots exactly like the ones it replaces.

6. **Point the entry surfaces at it** — `CLAUDE.md`, `README.md`, and `docs/ARCHITECTURE.md` reference
   `DECISIONS.md` as the decision layer. Keep this to a pointer line each: adding narrative to
   `CLAUDE.md` is the rebloat the diet work explicitly forbids.

## Non-goals
No deletion of spike docs. No rewriting of evidence or of any retracted-and-corrected claim. No new
decisions — this records what exists. No line-count target: reduction is a side effect of
de-duplication, never the objective.

## Acceptance criteria
- `DECISIONS.md` exists; D1–D11 and the NORTH_STAR bets/NOs are represented with IDs preserved.
- Every row has a working evidence pointer; every spike doc has a status banner naming a real row.
- At least one genuine cross-doc conflict is surfaced and recorded rather than silently resolved (the
  graph's four-source split is a known candidate — expect others).
- The currency check is red on a seeded violation in **both** directions and green on main.
- This item's own diff does not violate the Claim Duplication Rule — self-checked explicitly,
  including any count or version literal it introduces.
- `CLAUDE.md` / `README.md` / `ARCHITECTURE.md` each gain a pointer line only, no narrative.
- Doc-currency and all existing gates green.

## Outcomes Rubric
- One decision layer, superseded rows retained
- Spike docs banner-marked and preserved intact, evidence untouched
- Bidirectional currency check, red on seeded violation
- At least one real conflict surfaced, not smoothed over
- Self-consistent: the item does not break the rule it extends

## Status: done_with_escalation — SUPERSEDED (retired 2026-09-21, not implemented)
- **Why:** the problem ("no decision layer") was absorbed after this was written: `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` §"Owner decisions" is a dated, amended D1–D11 table (D4 note 2026-09-20, D9 amendment 2026-08-17) that every queue and memory now cites as the single home. The unimplemented remainder — status banners on each spike doc — is cosmetic and does not justify a run.
- **If revived:** scope it to "banner the 18 spike docs with live/superseded/historical + pointer to the D-row", nothing more.
