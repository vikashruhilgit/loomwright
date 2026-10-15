# automate-speed/18 — Lock the gains: history-reference lint and lowered ceilings

## Status: pending

## Problem
Items 13–16 move stories out of the runtime prompts and shrink them; item 17 caps them at their old size. Without a
lint, the next fix PR adds "the case seen on #NNN" back into a runtime prompt (runtime prompts carried ~300 incident
references on 2026-10-15, plan doc §Why now), and the ceilings stay at the pre-diet sizes, leaving the headroom to
regrow.

## Goal
<!-- bump: minor -->
A CI lint counts history references (`#NNN`, `<queue>/<NN>`, `YYYY-MM-DD`, `item NN`, `vX.Y.Z`) in runtime prompt
files against a committed baseline that may only go down, and every skill/command/agent ceiling is re-baselined to its
post-diet measure + ~10%.

## Scope
- `scripts/check-prompt-history-refs.sh` + `scripts/test-check-prompt-history-refs.sh`: scans `loomwright/agents/`,
  `loomwright/commands/`, `loomwright/skills/` (not `docs/`, not `docs/rationale/`, not CHANGELOG); per-file counts vs
  `loomwright/docs/prompt-history-refs-baseline.json`; a file above its baseline ⇒ exit 1 naming the file and the new
  references; a file below ⇒ prints "lower the baseline" (the PR that lowers it updates the json).
- Wire it into `.github/workflows/ci.yml` (root-scripts tests are listed explicitly there) and `scripts/ci-local.sh`.
- Re-baseline every ceiling in `prompt-token-budgets.json` to the measured size + ~10% and update the mirror table.
- `CLAUDE.md`: one line pointing at the lint (where a story goes instead: CHANGELOG or `docs/rationale/`).

## Invariants
- The lint is a gate: fail-CLOSED. Its reader of the baseline fails closed on a malformed json.
- Frozen example values that `check-doc-currency.sh` already exempts stay exempt (do not double-police them).

## Non-goals
- Removing the remaining references (the diet items did that; the baseline records what is left).

## Owner decisions (from _BACKLOG.md)
- D2.

## Acceptance criteria
- Given a runtime prompt with one added `#123` reference, then `check-prompt-history-refs.sh` exits 1 naming the file.
- Given the same reference in `docs/rationale/`, then it passes.
- Every ceiling in `prompt-token-budgets.json` is within ~10% of its current measure; `check-token-budget.sh` passes.
- The total runtime read set for one `/automate` item (the item 03 measure) is recorded in
  `docs/evidence/automate-speed-baseline.md` next to the 2026-10-15 baseline.

## Validation (must pass before merge)
1. `scripts/test-check-prompt-history-refs.sh`, `scripts/test-check-token-budget.sh`, `scripts/test-ci-local.sh`,
   `check-doc-currency.sh`; report `<passed>/<total>`.
2. Mutation controls: add a `#123` reference to a scratch runtime prompt ⇒ red; raise that file's baseline entry
   in the same change ⇒ still red (the test refuses any baseline entry that rose against the merge base).

## Depends on
13
14
15
16
17

## Touches
scripts/check-prompt-history-refs.sh
scripts/test-check-prompt-history-refs.sh
loomwright/docs/prompt-history-refs-baseline.json
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
.github/workflows/ci.yml
scripts/ci-local.sh
CLAUDE.md
docs/evidence/automate-speed-baseline.md
changelog.d/as18-lock-the-gains.md
