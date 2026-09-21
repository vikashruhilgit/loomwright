# 06 — One arm-2 run on corpus entry 3: can this eval measure quality at all? (Fix 5, D11)

**OPERATOR-RUN eval — /automate must NOT drive this** (same class as item 05).

## Problem
`post_merge_defects` showed zero discriminating power on entry #1 (0/0 both arms — the threshold
sits above the entire signal range for a well-specified additive requirement). Continuing the
corpus as-is buys rows of zeros at $200–400. Entries 2 and 3 are migrations across existing call
sites, where a missed site is a genuine defect above the threshold.

## Goal
Spend ~$60 to decide whether the eval corpus can measure quality layers before spending $200+.

## Scope
1. One Loomwright-default (arm-2) run on corpus entry 3 (per `FABLE_PARITY_EVAL.md` corpus table),
   run-time row per protocol.
2. Decision rule, pre-committed: if it returns `heal_iterations: 0` and 0 BLOCKING/HIGH again →
   STOP the corpus; record that the corpus cannot measure quality layers (worth more than four more
   zero rows). If defects appear above threshold → the corpus is viable; plan remaining entries.
3. `wall_tokens` note applies: cost is the comparator; token columns under-count sub-agents ~6×.

## Non-goals
No new metrics without a loud additive amendment. No arm-1/arm-3 runs here.

## Acceptance criteria
- Row recorded at run time; STOP/CONTINUE decision written into FABLE_PARITY_EVAL with the
  pre-committed rule cited.

## Outcomes Rubric
- Run executed and recorded per protocol
- Pre-committed STOP/CONTINUE decision honored and written down
